import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {

    private var overlayWindow: PetOverlayWindow?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    private let rosterModel = PetRosterModel()
    private let dropController = FileDropController()
    private let timerManager = PetTimerManager()
    private let timerNotifier = TimerNotifier()
    private let clickController = PetClickController()
    private var timerPopover: NSPopover?
    private var timerPopoverModel: TimerPopoverModel?
    /// Scene identity for each enabled kind — the per-id plumbing into the scene.
    private var instanceIDs: [PetKind: UUID] = [:]

    private static let enabledPetsDefaultsKey = "enabledPetKinds"
    private static let attacksFilesDefaultsKey = "attacksFilesPetKinds"
    private static let timerPetsDefaultsKey = "timerPetKinds"
    private static let timerSoundsDefaultsKey = "timerSoundsEnabled"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpOverlayWindow()

        // Restore the roster before building UI; first launch falls back to
        // the original single-pet default.
        let saved = loadKinds(forKey: Self.enabledPetsDefaultsKey) ?? [.girl]
        rosterModel.enabledKinds = saved
        rosterModel.attacksFiles = loadKinds(forKey: Self.attacksFilesDefaultsKey) ?? []
        rosterModel.timerPets = loadKinds(forKey: Self.timerPetsDefaultsKey) ?? []
        rosterModel.timerSoundsOn =
            UserDefaults.standard.object(forKey: Self.timerSoundsDefaultsKey) as? Bool ?? true
        for kind in PetKind.allCases where saved.contains(kind) {
            addPetToDock(kind)
        }

        wireRosterModel()
        setUpStatusItem()
        setUpFileDrops()
        setUpTimers()
    }

    // MARK: - Pet timers

    private func setUpTimers() {
        timerNotifier.setUp()
        timerNotifier.onDismiss = { [weak self] kind in
            self?.timerManager.dismissDone(kind: kind)
        }
        timerNotifier.onSnooze = { [weak self] kind in
            self?.timerManager.snooze(kind: kind)
        }
        timerNotifier.onNewTimer = { [weak self] kind in
            guard let self else { return }
            timerManager.dismissDone(kind: kind)
            // No pet panel to anchor to from a notification click — fall
            // back to the menu bar item.
            if let button = statusItem?.button {
                showTimerPopover(for: kind, anchor: button)
            }
        }

        timerManager.onTick = { [weak self] kind, state in
            guard let self, let id = instanceIDs[kind] else { return }
            overlayWindow?.setTimerProgress(id: id, remainingFraction: remainingFraction(of: state))
        }
        timerManager.onCompleted = { [weak self] kind, state in
            guard let self else { return }
            if let id = instanceIDs[kind] {
                overlayWindow?.setTimerDone(id: id)
            }
            if rosterModel.timerSoundsOn {
                NSSound(named: "Glass")?.play()
            }
            timerNotifier.notifyDone(kind: kind, note: state.note)
            // If the popover is open on this pet, flip it to the done UI so
            // it can't offer stale running-timer controls.
            if let model = timerPopoverModel, model.kind == kind {
                model.mode = .done
            }
        }
        timerManager.onChanged = { [weak self] kind, state in
            self?.syncTimerVisuals(for: kind, state: state)
        }

        clickController.targetsProvider = { [weak self] in
            guard let self, let window = overlayWindow else { return [] }
            return window.timerClickTargets(for: rosterModel.timerPets) { kind in
                self.timerTooltip(for: kind)
            }
        }
        clickController.onClick = { [weak self] kind, anchor in
            self?.showTimerPopover(for: kind, anchor: anchor)
        }
        clickController.start()

        // Reconcile persisted timers slightly after launch: gives the
        // notification-authorization check a beat to come back, so a timer
        // that expired while the app was closed lands as a real notification
        // instead of the toast fallback.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.timerManager.loadAndReconcile()
        }
    }

    /// Reflects a timer state change on the pet: progress ring while running
    /// (the pet keeps roaming — the ring follows), celebration + glow when
    /// done, everything cleared when the timer goes away.
    private func syncTimerVisuals(for kind: PetKind, state: PetTimerState?) {
        guard let id = instanceIDs[kind], let window = overlayWindow else { return }
        if let state {
            switch state.status {
            case .running:
                // Planted only while the popover is open on this pet, so the
                // bubble doesn't drift after a strolling anchor.
                let popoverOpen = timerPopover != nil && timerPopoverModel?.kind == kind
                window.setPetFocused(id: id, popoverOpen)
                window.setTimerProgress(id: id, remainingFraction: remainingFraction(of: state))
            case .done:
                window.setTimerDone(id: id) // plants itself until acknowledged
            }
        } else {
            window.clearTimerVisuals(id: id)
        }
    }

    private func remainingFraction(of state: PetTimerState) -> CGFloat {
        let total = state.endsAt.timeIntervalSince(state.startedAt)
        guard total > 0 else { return 0 }
        return CGFloat(max(0, min(1, state.remaining / total)))
    }

    private func timerTooltip(for kind: PetKind) -> String {
        guard let state = timerManager.timers[kind] else {
            return "Click to set a timer"
        }
        let note = state.note.isEmpty ? "" : " — \(state.note)"
        switch state.status {
        case .running:
            return "\(PetTimerState.format(state.remaining)) left\(note)"
        case .done:
            return "Time's up!\(note)"
        }
    }

    private func showTimerPopover(for kind: PetKind, anchor: NSView) {
        timerPopover?.performClose(nil)

        let model = TimerPopoverModel(kind: kind, state: timerManager.timers[kind])
        model.onStart = { [weak self] minutes, note in
            guard let self else { return }
            timerNotifier.requestAuthorizationIfNeeded()
            timerManager.start(kind: kind, minutes: minutes, note: note)
            timerPopover?.performClose(nil)
        }
        model.onAddMinutes = { [weak self, weak model] minutes in
            guard let self else { return }
            timerManager.addMinutes(minutes, for: kind)
            if let endsAt = timerManager.timers[kind]?.endsAt {
                model?.endsAt = endsAt
            }
        }
        model.onNoteEdited = { [weak self] note in
            self?.timerManager.updateNote(note, for: kind)
        }
        model.onCancelTimer = { [weak self] in
            self?.timerManager.cancel(kind: kind)
            self?.timerPopover?.performClose(nil)
        }
        model.onRestart = { [weak self] in
            self?.timerManager.restart(kind: kind)
            self?.timerPopover?.performClose(nil)
        }
        model.onDismissDone = { [weak self] in
            self?.timerManager.dismissDone(kind: kind)
            self?.timerPopover?.performClose(nil)
        }

        let popover = NSPopover()
        popover.behavior = .transient // Esc / click-outside cancels
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: TimerPopoverView(model: model)
        )
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        // Same accessory-app quirk as the roster popover: no key focus means
        // the text fields can't be typed in.
        popover.contentViewController?.view.window?.makeKey()

        timerPopover = popover
        timerPopoverModel = model

        // Plant the pet while the popover is up so the bubble doesn't chase
        // a strolling pet; popoverDidClose re-syncs from the timer state.
        if let id = instanceIDs[kind] {
            overlayWindow?.setPetFocused(id: id, true)
        }
    }

    func popoverDidClose(_ notification: Notification) {
        guard (notification.object as? NSPopover) === timerPopover else { return }
        let kind = timerPopoverModel?.kind
        timerPopover = nil
        timerPopoverModel = nil
        if let kind {
            syncTimerVisuals(for: kind, state: timerManager.timers[kind])
        }
    }

    // MARK: - File-attack drops

    private func setUpFileDrops() {
        dropController.targetsProvider = { [weak self] in
            guard let self, let window = overlayWindow else { return [] }
            return window.fileDropTargets(for: rosterModel.attacksFiles)
        }
        dropController.onDrop = { [weak self] id, urls in
            guard let self else { return }
            overlayWindow?.triggerAttack(id: id) {
                var trashedNames: [String] = []
                for url in urls {
                    do {
                        // Recoverable by design: Trash, never a permanent delete.
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                        trashedNames.append(url.lastPathComponent)
                    } catch {
                        NSSound.beep()
                        NSLog("LazyPets: couldn't trash \(url.path): \(error)")
                    }
                }
                if let name = trashedNames.first {
                    TrashToast.show(message: trashedNames.count == 1
                        ? "“\(name)” moved to Bin"
                        : "\(trashedNames.count) files moved to Bin")
                }
            }
        }
        dropController.onHover = { [weak self] id, hovering in
            self?.overlayWindow?.setPetHighlighted(id: id, hovering)
        }
        dropController.start()
    }

    // MARK: - Roster actions

    private func wireRosterModel() {
        rosterModel.onToggle = { [weak self] kind, enabled in
            guard let self else { return }
            if enabled {
                addPetToDock(kind)
            } else {
                removePetFromDock(kind)
            }
            saveKinds(rosterModel.enabledKinds, forKey: Self.enabledPetsDefaultsKey)
        }
        rosterModel.onAttacksFilesToggle = { [weak self] _, _ in
            guard let self else { return }
            saveKinds(rosterModel.attacksFiles, forKey: Self.attacksFilesDefaultsKey)
        }
        rosterModel.onTimerToggle = { [weak self] kind, enabled in
            guard let self else { return }
            saveKinds(rosterModel.timerPets, forKey: Self.timerPetsDefaultsKey)
            if !enabled {
                // Turning the feature off ends any active timer for the pet.
                timerManager.cancel(kind: kind)
            }
        }
        rosterModel.onTimerSoundsToggle = { on in
            UserDefaults.standard.set(on, forKey: Self.timerSoundsDefaultsKey)
        }
        rosterModel.onAttack = { [weak self] kind in
            guard let self, let id = instanceIDs[kind] else { return }
            overlayWindow?.triggerAttack(id: id)
        }
        rosterModel.onHideAll = { [weak self] hidden in
            self?.overlayWindow?.setAllPetsHidden(hidden)
        }
        rosterModel.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private func addPetToDock(_ kind: PetKind) {
        guard instanceIDs[kind] == nil else { return }
        let instance = PetInstance(kind: kind)
        instanceIDs[kind] = instance.id
        overlayWindow?.addPet(instance)
        // A timer may have kept counting while the pet was off the Dock —
        // restore its focused stance/badge on the fresh node.
        syncTimerVisuals(for: kind, state: timerManager.timers[kind])
    }

    private func removePetFromDock(_ kind: PetKind) {
        guard let id = instanceIDs.removeValue(forKey: kind) else { return }
        overlayWindow?.removePet(id: id)
    }

    // MARK: - Persistence

    private func loadKinds(forKey key: String) -> Set<PetKind>? {
        guard let raw = UserDefaults.standard.stringArray(forKey: key) else {
            return nil
        }
        return Set(raw.compactMap(PetKind.init(rawValue:)))
    }

    private func saveKinds(_ kinds: Set<PetKind>, forKey key: String) {
        // Store in stable declaration order for a tidy plist.
        let raw = PetKind.allCases.filter(kinds.contains).map(\.rawValue)
        UserDefaults.standard.set(raw, forKey: key)
    }

    // MARK: - Menu bar popover

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "LazyPets")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient // closes on any outside click
        popover.contentViewController = NSHostingController(
            rootView: PetRosterView(model: rosterModel)
        )
        self.popover = popover
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            // Accessory apps don't get key focus automatically; without this
            // the popover's controls can't be clicked reliably.
            popover.contentViewController?.view.window?.makeKey()
            // On crowded menu bars the popover can land too high — its top
            // ends up above the screen edge, overlapping the menu bar.
            // Clamp it to hang just below the bar (no-op when placed right).
            if let window = popover.contentViewController?.view.window,
               let screen = window.screen ?? NSScreen.main {
                let maxTop = screen.visibleFrame.maxY - 2
                if window.frame.maxY > maxTop {
                    window.setFrameTopLeftPoint(NSPoint(x: window.frame.minX, y: maxTop))
                }
            }
        }
    }

    // MARK: - Overlay

    private func setUpOverlayWindow() {
        let window = PetOverlayWindow()
        window.orderFrontRegardless()
        overlayWindow = window
    }
}

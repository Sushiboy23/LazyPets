import AppKit

/// Routes pets across displays: one PetOverlayWindow per display that
/// currently has pets, pin/orphan bookkeeping, and reconciliation when
/// screens connect or disconnect (in any order, down to one and back up).
///
/// It exposes the same per-pet API the single overlay window used to, so the
/// rest of the app is display-agnostic: mutations are broadcast to every
/// window and the scenes ignore ids they don't host.
final class PetOverlayCoordinator {

    /// The pet's pinned display UUID, or nil for Default. Supplied by
    /// AppDelegate from the roster model.
    var pinnedDisplayUUID: (PetKind) -> String? = { _ in nil }
    /// Fired after relocation recreates pet nodes on another display, so
    /// per-pet visual state (timer badges, focus) can be re-applied.
    var onPetsRelocated: (() -> Void)?

    private var windows: [String: PetOverlayWindow] = [:]
    private var instances: [UUID: PetInstance] = [:]
    private var currentDisplay: [UUID: String] = [:]
    /// Where a displaced pinned pet belongs — set when its pinned display
    /// vanishes, cleared when it reconnects (snap back) or the user
    /// reassigns the pet. Never set for unpinned pets: they have no home to
    /// restore, they just stay wherever the fallback put them.
    private var orphanedDisplayUUID: [PetKind: String] = [:]

    private var allHidden = false
    private var knownUUIDs: Set<String>
    /// The display active at app launch — where Default pets go, preserving
    /// the pre-pinning behavior exactly.
    private let defaultDisplayUUID: String?

    private var reconcileDebounce: DispatchWorkItem?

    init() {
        knownUUIDs = Set(ConnectedDisplays.all().map(\.uuid))
        defaultDisplayUUID = ConnectedDisplays.mainUUID
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    // MARK: - Pets

    func addPet(_ instance: PetInstance) {
        instances[instance.id] = instance
        place(instance, on: targetDisplay(for: instance.kind))
    }

    func removePet(id: UUID) {
        if let instance = instances.removeValue(forKey: id) {
            orphanedDisplayUUID[instance.kind] = nil
        }
        if let uuid = currentDisplay.removeValue(forKey: id) {
            windows[uuid]?.removePet(id: id)
        }
        pruneEmptyWindows()
    }

    /// Re-places a pet after its assignment changed in the UI. Pinning moves
    /// it (or orphans it if the display is unplugged right now); switching
    /// back to Default leaves it where it stands — there's no deliberate
    /// home to enforce anymore.
    func assignmentChanged(for kind: PetKind) {
        orphanedDisplayUUID[kind] = nil
        guard let (id, instance) = instances.first(where: { $0.value.kind == kind }) else { return }
        if pinnedDisplayUUID(kind) != nil {
            movePet(id: id, instance: instance, to: targetDisplay(for: kind))
            onPetsRelocated?()
        }
    }

    // MARK: - Screen reconciliation

    @objc private func screensChanged() {
        // Hot-plugs fire this several times in quick succession; act once
        // things settle. A dock/hub swap that ends with the same display set
        // resolves to a no-op in reconcile().
        reconcileDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reconcile() }
        reconcileDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func reconcile() {
        let connected = Set(ConnectedDisplays.all().map(\.uuid))
        // Unchanged set = nothing to do. This also guards display sleep:
        // sleeping monitors stay enumerated in NSScreen.screens, so no
        // reshuffle happens. (Mirroring collapses the set — treated like a
        // disconnect, restored when un-mirrored.)
        guard connected != knownUUIDs else { return }
        knownUUIDs = connected
        var relocated = false

        // Pets on vanished displays fall back to the main display. Pinned
        // pets remember where they belong; unpinned ones just land there.
        for (id, uuid) in currentDisplay where !connected.contains(uuid) {
            guard let instance = instances[id] else { continue }
            if pinnedDisplayUUID(instance.kind) == uuid {
                orphanedDisplayUUID[instance.kind] = uuid
            }
            movePet(id: id, instance: instance, to: mainUUID)
            relocated = true
        }

        // Reconnects: each displaced pinned pet snaps back to its own
        // display, whatever order the monitors come back in.
        for (id, instance) in instances {
            guard let orphaned = orphanedDisplayUUID[instance.kind],
                  connected.contains(orphaned) else { continue }
            orphanedDisplayUUID[instance.kind] = nil
            movePet(id: id, instance: instance, to: orphaned)
            relocated = true
        }

        if relocated {
            onPetsRelocated?()
        }
    }

    // MARK: - Placement

    private func targetDisplay(for kind: PetKind) -> String {
        if let pin = pinnedDisplayUUID(kind) {
            if isConnected(pin) {
                orphanedDisplayUUID[kind] = nil
                return pin
            }
            orphanedDisplayUUID[kind] = pin
            return mainUUID
        }
        if let defaultDisplayUUID, isConnected(defaultDisplayUUID) {
            return defaultDisplayUUID
        }
        return mainUUID
    }

    private var mainUUID: String {
        ConnectedDisplays.mainUUID ?? knownUUIDs.first ?? ""
    }

    private func isConnected(_ uuid: String) -> Bool {
        ConnectedDisplays.screen(forUUID: uuid) != nil
    }

    private func place(_ instance: PetInstance, on uuid: String) {
        window(for: uuid).addPet(instance)
        currentDisplay[instance.id] = uuid
    }

    private func movePet(id: UUID, instance: PetInstance, to uuid: String) {
        if let from = currentDisplay[id] {
            guard from != uuid else { return }
            windows[from]?.removePet(id: id)
        }
        // addPet spawns at a random x in the middle band, so several pets
        // falling back to the same display don't stack on one spot.
        place(instance, on: uuid)
        pruneEmptyWindows()
    }

    private func window(for uuid: String) -> PetOverlayWindow {
        if let existing = windows[uuid] {
            return existing
        }
        let window = PetOverlayWindow(displayUUID: uuid)
        windows[uuid] = window
        window.setAllPetsHidden(allHidden) // also orders front when visible
        return window
    }

    private func pruneEmptyWindows() {
        let used = Set(currentDisplay.values)
        for (uuid, window) in windows where !used.contains(uuid) {
            window.tearDown()
            window.orderOut(nil)
            windows[uuid] = nil
        }
    }

    // MARK: - Forwarding (broadcast; scenes ignore ids they don't host)

    func triggerAttack(id: UUID, then: (() -> Void)? = nil) {
        for window in windows.values {
            window.triggerAttack(id: id, then: then)
        }
    }

    func beginPetDrag(id: UUID, at screenPoint: NSPoint) {
        for window in windows.values {
            window.beginPetDrag(id: id, at: screenPoint)
        }
    }

    func dragPet(id: UUID, to screenPoint: NSPoint) {
        for window in windows.values {
            window.dragPet(id: id, to: screenPoint)
        }
    }

    func endPetDrag(id: UUID) {
        for window in windows.values {
            window.endPetDrag(id: id)
        }
    }

    func setPetHighlighted(id: UUID, _ highlighted: Bool) {
        for window in windows.values {
            window.setPetHighlighted(id: id, highlighted)
        }
    }

    func setPetFocused(id: UUID, _ focused: Bool) {
        for window in windows.values {
            window.setPetFocused(id: id, focused)
        }
    }

    func setTimerProgress(id: UUID, remainingFraction: CGFloat) {
        for window in windows.values {
            window.setTimerProgress(id: id, remainingFraction: remainingFraction)
        }
    }

    func setTimerDone(id: UUID) {
        for window in windows.values {
            window.setTimerDone(id: id)
        }
    }

    func clearTimerVisuals(id: UUID) {
        for window in windows.values {
            window.clearTimerVisuals(id: id)
        }
    }

    func fileDropTargets(for kinds: Set<PetKind>) -> [FileDropTarget] {
        windows.values.flatMap { $0.fileDropTargets(for: kinds) }
    }

    func timerClickTargets(for kinds: Set<PetKind>, tooltip: (PetKind) -> String?) -> [PetClickTarget] {
        windows.values.flatMap { $0.timerClickTargets(for: kinds, tooltip: tooltip) }
    }

    func setAllPetsHidden(_ hidden: Bool) {
        allHidden = hidden
        for window in windows.values {
            window.setAllPetsHidden(hidden)
        }
    }
}

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var overlayWindow: PetOverlayWindow?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    private let rosterModel = PetRosterModel()
    /// Scene identity for each enabled kind — the per-id plumbing into the scene.
    private var instanceIDs: [PetKind: UUID] = [:]

    private static let enabledPetsDefaultsKey = "enabledPetKinds"

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpOverlayWindow()

        // Restore the roster before building UI; first launch falls back to
        // the original single-pet default.
        let saved = loadEnabledKinds() ?? [.girl]
        rosterModel.enabledKinds = saved
        for kind in PetKind.allCases where saved.contains(kind) {
            addPetToDock(kind)
        }

        wireRosterModel()
        setUpStatusItem()
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
            saveEnabledKinds(rosterModel.enabledKinds)
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
    }

    private func removePetFromDock(_ kind: PetKind) {
        guard let id = instanceIDs.removeValue(forKey: kind) else { return }
        overlayWindow?.removePet(id: id)
    }

    // MARK: - Persistence

    private func loadEnabledKinds() -> Set<PetKind>? {
        guard let raw = UserDefaults.standard.stringArray(forKey: Self.enabledPetsDefaultsKey) else {
            return nil
        }
        return Set(raw.compactMap(PetKind.init(rawValue:)))
    }

    private func saveEnabledKinds(_ kinds: Set<PetKind>) {
        // Store in stable declaration order for a tidy plist.
        let raw = PetKind.allCases.filter(kinds.contains).map(\.rawValue)
        UserDefaults.standard.set(raw, forKey: Self.enabledPetsDefaultsKey)
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
        }
    }

    // MARK: - Overlay

    private func setUpOverlayWindow() {
        let window = PetOverlayWindow()
        window.orderFrontRegardless()
        overlayWindow = window
    }
}

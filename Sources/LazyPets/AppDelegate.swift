import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    private var overlayWindow: PetOverlayWindow?
    private var statusItem: NSStatusItem?
    private var petItems: [NSMenuItem] = []
    private var attackItem: NSMenuItem?

    private var selectedPet: PetKind = .girl

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        setUpOverlayWindow()
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "LazyPets")
        }

        let menu = NSMenu()
        // Title flips between Hide/Show as the pet is toggled.
        let toggleItem = NSMenuItem(title: "Hide Pet", action: #selector(toggleVisibility), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        // One checkable item per pet; the checkmark tracks `selectedPet`.
        for kind in PetKind.allCases {
            let petItem = NSMenuItem(title: kind.rawValue, action: #selector(selectPet(_:)), keyEquivalent: "")
            petItem.target = self
            petItem.representedObject = kind.rawValue
            petItem.state = kind == selectedPet ? .on : .off
            menu.addItem(petItem)
            petItems.append(petItem)
        }

        menu.addItem(.separator())

        // Plays one of the knight's three attack animations at random.
        // Disabled for pets without attack art (handled in validateMenuItem).
        let attack = NSMenuItem(title: "Attack!", action: #selector(triggerAttack), keyEquivalent: "")
        attack.target = self
        menu.addItem(attack)
        attackItem = attack

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit LazyPets", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func selectPet(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let kind = PetKind(rawValue: rawValue) else { return }
        selectedPet = kind
        for item in petItems {
            item.state = item == sender ? .on : .off
        }
        overlayWindow?.selectPet(kind)
    }

    @objc private func triggerAttack() {
        overlayWindow?.triggerAttack()
    }

    // Grays out "Attack!" while a pet with no attack animations is selected.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem == attackItem {
            return PetAnimations.set(for: selectedPet).attacks.isEmpty == false
        }
        return true
    }

    @objc private func toggleVisibility(_ sender: NSMenuItem) {
        guard let window = overlayWindow else { return }
        let hide = window.isVisible
        window.setPetHidden(hide)
        sender.title = hide ? "Show Pet" : "Hide Pet"
    }

    // MARK: - Overlay

    private func setUpOverlayWindow() {
        let window = PetOverlayWindow()
        window.orderFrontRegardless()
        overlayWindow = window
    }
}

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var overlayWindow: PetOverlayWindow?
    private var statusItem: NSStatusItem?

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
        let toggleItem = NSMenuItem(title: "Show Pet", action: #selector(toggleVisibility), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = .on
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit LazyPets", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleVisibility(_ sender: NSMenuItem) {
        guard let window = overlayWindow else { return }
        if window.isVisible {
            window.orderOut(nil)
            sender.state = .off
        } else {
            window.orderFrontRegardless()
            sender.state = .on
        }
    }

    // MARK: - Overlay

    private func setUpOverlayWindow() {
        let window = PetOverlayWindow()
        window.orderFrontRegardless()
        overlayWindow = window
    }
}

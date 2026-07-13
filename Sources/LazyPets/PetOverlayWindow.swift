import AppKit
import SpriteKit

/// Transparent, click-through, always-on-top panel that sits above the Dock
/// and hosts the SpriteKit pet scene. Repositions itself whenever the screen
/// configuration or Dock geometry changes.
final class PetOverlayWindow: NSPanel {

    // Extra height above the Dock strip so the pet has room to bob/jump.
    private let petHeadroom: CGFloat = 80

    private let skView = SKView()
    private var petScene: PetScene?

    init() {
        let initialRect = NSRect(x: 0, y: 0, width: 400, height: 100)
        super.init(
            contentRect: initialRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        ignoresMouseEvents = true // click-through by default; flip per-pet if we add drag/pet interactions later
        isMovableByWindowBackground = false

        setUpSKView()
        repositionOverDock()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositionOverDock),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func setUpSKView() {
        skView.allowsTransparency = true
        skView.wantsLayer = true
        skView.layer?.backgroundColor = .clear
        contentView = skView
    }

    @objc private func repositionOverDock() {
        guard let screen = DockGeometry.dockScreen(),
              let dockRect = DockGeometry.dockRect(on: screen) else { return }

        let frame = NSRect(
            x: dockRect.minX,
            y: dockRect.minY,
            width: dockRect.width,
            height: dockRect.height + petHeadroom
        )
        setFrame(frame, display: true)

        if let scene = petScene {
            scene.size = frame.size
            scene.dockHeight = dockRect.height
        } else {
            let scene = PetScene(size: frame.size)
            scene.dockHeight = dockRect.height
            scene.scaleMode = .resizeFill
            skView.presentScene(scene)
            petScene = scene
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

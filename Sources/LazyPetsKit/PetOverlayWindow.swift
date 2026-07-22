import AppKit
import SpriteKit

/// Transparent, click-through, always-on-top panel hosting the SpriteKit pet
/// scene for ONE display. The PetOverlayCoordinator creates one of these per
/// display that currently has pets and moves pets between them; this window
/// only tracks its own display's Dock geometry.
final class PetOverlayWindow: NSPanel {

    // Extra height above the Dock strip so the pet has room to bob/jump.
    // Must exceed the tallest sprite frame × its pet's pixelScale or the
    // sprite gets clipped by the window edge. Current max: warrior, 250px × 0.7.
    private let petHeadroom: CGFloat = 190

    private let skView = SKView()
    private var petScene: PetScene?
    private var dockWatchTimer: Timer?

    /// The physical display this window belongs to (EDID UUID). When this
    /// screen shows a Dock its pets stand on top of it; when it doesn't,
    /// they stand flush on the screen's bottom edge.
    let displayUUID: String

    /// Re-resolved on every use — NSScreen instances are recreated on
    /// configuration changes. Nil while the display is disconnected; no
    /// fallback here, the coordinator relocates pets instead. (Named to
    /// avoid NSWindow's own `screen` property.)
    private var assignedScreen: NSScreen? {
        ConnectedDisplays.screen(forUUID: displayUUID)
    }

    init(displayUUID: String) {
        self.displayUUID = displayUUID
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
        // NSPanel defaults this to true, which hides the overlay as soon as
        // the app deactivates — e.g. clicking away after unhiding pets from
        // the popover (the popover is the only thing that ever activates
        // this accessory app). Same fix as the file-drop panels.
        hidesOnDeactivate = false

        setUpSKView()
        repositionOverDock()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(repositionOverDock),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        // Switching Spaces can move the Dock onto or off the home display
        // (with "Displays have separate Spaces", it follows the active one).
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(repositionOverDock),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        // No notification fires when the Dock arrives on / leaves the home
        // display (mouse held at another display's bottom edge) or resizes,
        // so poll as a catch-all. repositionOverDock early-returns when
        // nothing moved, so the steady-state cost is two screen-geometry
        // reads and a rect compare.
        dockWatchTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.repositionOverDock()
        }
    }

    /// Stops the dock-follow poll before the coordinator discards the window
    /// (the run loop would otherwise keep the timer alive indefinitely).
    func tearDown() {
        dockWatchTimer?.invalidate()
        dockWatchTimer = nil
    }

    private func setUpSKView() {
        skView.allowsTransparency = true
        skView.wantsLayer = true
        skView.layer?.backgroundColor = .clear
        contentView = skView
    }

    // MARK: - Pet control (forwarded from the status-item popover)

    func addPet(_ instance: PetInstance) {
        petScene?.addPet(instance)
    }

    func removePet(id: UUID) {
        petScene?.removePet(id: id)
    }

    func triggerAttack(id: UUID, then: (() -> Void)? = nil) {
        petScene?.triggerAttack(id: id, then: then)
    }

    func setPetHighlighted(id: UUID, _ highlighted: Bool) {
        petScene?.setHighlight(id: id, highlighted)
    }

    /// Drop zones for pets that may attack dropped files, in screen coords.
    func fileDropTargets(for kinds: Set<PetKind>) -> [FileDropTarget] {
        guard isVisible, let scene = petScene else { return [] }
        return scene.attackablePetRects(of: kinds).map { target in
            FileDropTarget(id: target.id, screenRect: screenRect(fromSceneRect: target.rect, in: scene))
        }
    }

    /// Click zones for timer-enabled pets, in screen coords. `tooltip` lets
    /// the caller attach hover text (time remaining + note) per pet.
    func timerClickTargets(for kinds: Set<PetKind>, tooltip: (PetKind) -> String?) -> [PetClickTarget] {
        guard isVisible, let scene = petScene else { return [] }
        return scene.petRects(of: kinds).map { target in
            PetClickTarget(
                kind: target.kind,
                screenRect: screenRect(fromSceneRect: target.rect, in: scene),
                tooltip: tooltip(target.kind)
            )
        }
    }

    // MARK: - Drag to relocate (forwarded to the scene)

    func beginPetDrag(id: UUID, at screenPoint: NSPoint) {
        guard let scene = petScene else { return }
        scene.beginDrag(id: id, atSceneX: scenePoint(fromScreenPoint: screenPoint, in: scene).x)
    }

    func dragPet(id: UUID, to screenPoint: NSPoint) {
        guard let scene = petScene else { return }
        scene.dragPet(id: id, toSceneX: scenePoint(fromScreenPoint: screenPoint, in: scene).x)
    }

    func endPetDrag(id: UUID) {
        petScene?.endDrag(id: id)
    }

    // MARK: - Timer visuals (forwarded to the scene)

    func setPetFocused(id: UUID, _ focused: Bool) {
        petScene?.setFocused(id: id, focused)
    }

    func setTimerProgress(id: UUID, remainingFraction: CGFloat) {
        petScene?.setTimerProgress(id: id, remainingFraction: remainingFraction)
    }

    func setTimerDone(id: UUID) {
        petScene?.setTimerDone(id: id)
    }

    func clearTimerVisuals(id: UUID) {
        petScene?.clearTimer(id: id)
    }

    /// Scene rect → screen rect through the full chain — scene → SKView →
    /// window → screen — using SpriteKit/AppKit conversion APIs at each hop
    /// (scene and view coordinate systems are NOT interchangeable, even when
    /// the scene fills the view).
    private func screenRect(fromSceneRect rect: CGRect, in scene: PetScene) -> NSRect {
        let bottomLeft = scene.convertPoint(toView: rect.origin)
        let topRight = scene.convertPoint(toView: CGPoint(x: rect.maxX, y: rect.maxY))
        // convertPoint(toView:) may flip the y-axis, so normalize corners.
        let viewRect = NSRect(
            x: min(bottomLeft.x, topRight.x),
            y: min(bottomLeft.y, topRight.y),
            width: abs(topRight.x - bottomLeft.x),
            height: abs(topRight.y - bottomLeft.y)
        )
        return convertToScreen(skView.convert(viewRect, to: nil))
    }

    /// Inverse of `screenRect(fromSceneRect:)` for a single point: screen →
    /// window → SKView → scene, using the proper conversion API at each hop.
    private func scenePoint(fromScreenPoint point: NSPoint, in scene: PetScene) -> CGPoint {
        let windowPoint = convertPoint(fromScreen: point)
        return scene.convertPoint(fromView: skView.convert(windowPoint, from: nil))
    }

    /// Temporarily hides all pets: orders the overlay out *and* pauses the
    /// scene + every pet's behavior timers so hidden pets cost nothing.
    /// Showing again resumes each from a fresh idle.
    func setAllPetsHidden(_ hidden: Bool) {
        if hidden {
            orderOut(nil)
            petScene?.pauseAllPets()
            petScene?.isPaused = true
        } else {
            petScene?.isPaused = false
            petScene?.resumeAllPets()
            orderFrontRegardless()
        }
    }

    @objc private func repositionOverDock() {
        guard let screen = assignedScreen,
              let dockRect = DockGeometry.dockRect(on: screen) else { return }

        let frame = NSRect(
            x: dockRect.minX,
            y: dockRect.minY,
            width: dockRect.width,
            height: dockRect.height + petHeadroom
        )
        // Polled every second — skip the relayout when the Dock hasn't moved.
        if let scene = petScene, self.frame == frame, scene.dockHeight == dockRect.height {
            return
        }
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

import SpriteKit

/// Identity of an active pet on the Dock: *which pets exist* (id) is decoupled
/// from *which sprite set renders them* (kind), so the same kind could appear
/// twice someday without the scene caring.
struct PetInstance: Identifiable, Hashable {
    let id: UUID
    let kind: PetKind

    init(kind: PetKind, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
    }
}

/// Hosts any number of pet sprites that idle and periodically walk across the
/// width of the scene (which is sized to match the Dock). Pets overlap freely —
/// no spacing or collision logic.
final class PetScene: SKScene {

    var dockHeight: CGFloat = 60 {
        didSet { layoutPets() }
    }

    private var petNodes: [UUID: PetNode] = [:]
    private var timerBadges: [UUID: TimerBadgeNode] = [:]
    /// Pets in the timer-done state keep a static yellow tint until
    /// acknowledged; tracked so the drag-hover highlight doesn't erase it
    /// when the highlight clears.
    private var timerDoneTint: Set<UUID> = []

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        anchorPoint = .zero
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutPets()
    }

    // MARK: - Roster

    func addPet(_ instance: PetInstance) {
        guard petNodes[instance.id] == nil else { return }
        let node = PetNode(kind: instance.kind)
        petNodes[instance.id] = node
        addChild(node)

        // Spawn somewhere in the middle band so simultaneous pets don't stack
        // in exactly the same spot.
        let x = size.width > 0 ? CGFloat.random(in: size.width * 0.3...size.width * 0.7)
                               : size.width / 2
        node.position = CGPoint(x: x, y: dockHeight)
        node.walkableRange = 0...size.width
        node.stateMachine.start()
    }

    func removePet(id: UUID) {
        guard let node = petNodes.removeValue(forKey: id) else { return }
        node.stateMachine.stop()
        node.removeAllActions()
        node.removeFromParent()
        timerBadges[id]?.removeFromParent()
        timerBadges[id] = nil
        timerDoneTint.remove(id)
    }

    func triggerAttack(id: UUID, then: (() -> Void)? = nil) {
        petNodes[id]?.stateMachine.triggerAttack(then: then)
    }

    /// Current on-screen rects (scene == view == window coordinates, since the
    /// scene is anchor-zero and sized to the view) of pets of the given kinds
    /// that can attack — the drop zones for the file-attack feature. Uses the
    /// visible-body rect, not the full frame, so the drop glow hugs the
    /// character instead of the art's transparent padding box.
    func attackablePetRects(of kinds: Set<PetKind>) -> [(id: UUID, rect: CGRect)] {
        petNodes.compactMap { id, node in
            guard node.canAttack, kinds.contains(node.kind) else { return nil }
            return (id: id, rect: node.bodyFrame)
        }
    }

    /// Warning glow while a dragged file hovers over the pet: release = the
    /// pet attacks and the file goes to the Trash. Un-highlighting restores
    /// the timer-done tint if the pet is waiting to be acknowledged.
    func setHighlight(id: UUID, _ highlighted: Bool) {
        guard let node = petNodes[id] else { return }
        node.color = .systemYellow
        node.colorBlendFactor = highlighted ? 0.5 : (timerDoneTint.contains(id) ? 0.35 : 0)
    }

    // MARK: - Timer visuals

    /// Rects + kinds for the timer click zones (same coordinate contract as
    /// `attackablePetRects`: scene == view == window coordinates).
    func petRects(of kinds: Set<PetKind>) -> [(id: UUID, kind: PetKind, rect: CGRect)] {
        petNodes.compactMap { id, node in
            guard kinds.contains(node.kind) else { return nil }
            return (id: id, kind: node.kind, rect: node.bodyFrame)
        }
    }

    /// Plants the pet in place (or releases it to roam again). Focused pets
    /// keep idling where they stand so the "working" stance reads at a glance.
    func setFocused(id: UUID, _ focused: Bool) {
        petNodes[id]?.stateMachine.setHoldsPosition(focused)
    }

    /// Shows/updates the progress ring above the pet. 1 = full ring (just
    /// started), 0 = empty. Also resets any leftover done styling, so a
    /// snoozed/restarted timer returns to a plain countdown.
    func setTimerProgress(id: UUID, remainingFraction: CGFloat) {
        guard let node = petNodes[id] else { return }
        let badge: TimerBadgeNode
        if let existing = timerBadges[id] {
            badge = existing
        } else {
            badge = TimerBadgeNode()
            addChild(badge)
            timerBadges[id] = badge
        }
        badge.setRemaining(remainingFraction)
        badge.position = badgePosition(for: node)
        if timerDoneTint.remove(id) != nil {
            node.colorBlendFactor = 0
        }
    }

    /// Timer hit zero: celebration animation, pulsing alarm badge, and a
    /// steady glow that stays until the user acknowledges. The pet plants
    /// where it stands so it's easy to click.
    func setTimerDone(id: UUID) {
        guard let node = petNodes[id] else { return }
        setTimerProgress(id: id, remainingFraction: 0)
        timerBadges[id]?.showDone()
        timerDoneTint.insert(id)
        node.color = .systemYellow
        // A property, not an SKAction — the frame steppers call
        // removeAllActions() on every state change and would kill a pulse.
        node.colorBlendFactor = 0.35
        node.stateMachine.setHoldsPosition(true)
        node.stateMachine.triggerCelebration()
    }

    /// Removes all timer styling and lets the pet roam again.
    func clearTimer(id: UUID) {
        timerBadges[id]?.removeFromParent()
        timerBadges[id] = nil
        timerDoneTint.remove(id)
        petNodes[id]?.colorBlendFactor = 0
        petNodes[id]?.stateMachine.setHoldsPosition(false)
    }

    /// Badges are scene-level siblings (not pet children) so the pets'
    /// mirroring and per-kind scaling can't distort them; ride along here.
    override func update(_ currentTime: TimeInterval) {
        for (id, badge) in timerBadges {
            guard let node = petNodes[id] else { continue }
            badge.position = badgePosition(for: node)
        }
    }

    private func badgePosition(for node: PetNode) -> CGPoint {
        CGPoint(x: node.position.x, y: node.bodyFrame.maxY + 14)
    }

    /// Stops every pet's behavior timers (used while the overlay is hidden).
    func pauseAllPets() {
        for node in petNodes.values {
            node.stateMachine.stop()
        }
    }

    /// Resumes every pet from a fresh idle.
    func resumeAllPets() {
        for node in petNodes.values {
            node.stateMachine.restart()
        }
    }

    /// Re-pins every pet to the Dock strip after the scene or Dock resizes.
    /// Pets are bottom-anchored, so their position *is* the point their feet
    /// stand on.
    private func layoutPets() {
        for node in petNodes.values {
            node.walkableRange = 0...size.width
            node.position = CGPoint(
                x: min(max(node.position.x, 0), size.width),
                y: dockHeight
            )
        }
    }
}

/// Progress ring that floats above a pet on a timer: remaining time as a
/// draining arc, flipping to a pulsing "!" alarm at zero.
private final class TimerBadgeNode: SKNode {

    private let radius: CGFloat = 9
    private let backdrop = SKShapeNode()
    private let arc = SKShapeNode()

    override init() {
        super.init()
        zPosition = 50
        backdrop.path = CGPath(
            ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2),
            transform: nil
        )
        backdrop.fillColor = NSColor.black.withAlphaComponent(0.4)
        backdrop.strokeColor = NSColor.white.withAlphaComponent(0.3)
        backdrop.lineWidth = 1
        addChild(backdrop)

        arc.fillColor = .clear
        arc.strokeColor = .systemYellow
        arc.lineWidth = 3
        arc.lineCap = .round
        addChild(arc)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 1 = full ring (just started), 0 = empty (time's up). Also resets any
    /// done styling so snooze/restart returns to a plain countdown.
    func setRemaining(_ fraction: CGFloat) {
        removeAllActions()
        setScale(1)
        childNode(withName: "mark")?.removeFromParent()
        backdrop.fillColor = NSColor.black.withAlphaComponent(0.4)

        let clamped = max(0, min(1, fraction))
        guard clamped > 0 else {
            arc.path = nil
            return
        }
        let start = CGFloat.pi / 2 // 12 o'clock, draining clockwise
        let path = CGMutablePath()
        path.addArc(
            center: .zero,
            radius: radius,
            startAngle: start,
            endAngle: start - 2 * .pi * clamped,
            clockwise: true
        )
        arc.path = path
    }

    func showDone() {
        arc.path = nil
        backdrop.fillColor = NSColor.systemYellow.withAlphaComponent(0.9)
        let mark = SKLabelNode(text: "!")
        mark.name = "mark"
        mark.fontName = "Menlo-Bold"
        mark.fontSize = 12
        mark.fontColor = .black
        mark.verticalAlignmentMode = .center
        addChild(mark)
        run(.repeatForever(.sequence([
            .scale(to: 1.3, duration: 0.35),
            .scale(to: 1.0, duration: 0.35),
        ])))
    }
}

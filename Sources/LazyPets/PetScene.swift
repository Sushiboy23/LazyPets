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
    /// pet attacks and the file goes to the Trash.
    func setHighlight(id: UUID, _ highlighted: Bool) {
        guard let node = petNodes[id] else { return }
        node.color = .systemYellow
        node.colorBlendFactor = highlighted ? 0.5 : 0
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

import SpriteKit

/// Hosts a single pet sprite that idles and periodically walks/runs across
/// the width of the scene (which is sized to match the Dock).
final class PetScene: SKScene {

    var dockHeight: CGFloat = 60 {
        didSet { positionPetOnDock() }
    }

    let pet = PetNode()

    override func didMove(to view: SKView) {
        backgroundColor = .clear
        anchorPoint = .zero
        addChild(pet)
        positionPetOnDock()
        pet.stateMachine.start()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        positionPetOnDock()
    }

    private func positionPetOnDock() {
        // Pet is bottom-anchored, so its position *is* the point its feet stand
        // on — place that on top of the Dock strip.
        pet.position = CGPoint(x: size.width / 2, y: dockHeight)
        pet.walkableRange = 0...size.width
    }
}

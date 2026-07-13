import SpriteKit

/// Hosts a single pet sprite that idles and periodically walks/runs across
/// the width of the scene (which is sized to match the Dock).
final class PetScene: SKScene {

    var dockHeight: CGFloat = 60 {
        didSet { positionPetOnDock() }
    }

    private let pet = PetNode()

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
        // Vertically: feet rest on top of the Dock strip.
        pet.position = CGPoint(x: size.width / 2, y: dockHeight + pet.size.height / 2)
        pet.walkableRange = 0...size.width
    }
}

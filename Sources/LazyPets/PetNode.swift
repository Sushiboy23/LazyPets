import AppKit
import SpriteKit

/// The pet itself: a sprite plus the state machine driving its idle/walk
/// behavior. v1 uses procedural placeholder art (a simple shape) so the app
/// is runnable without any asset pipeline; swap `makePlaceholderTexture`
/// for real sprite-sheet frames later without touching the state machine.
final class PetNode: SKSpriteNode {

    let stateMachine: PetStateMachine
    var walkableRange: ClosedRange<CGFloat> = 0...400

    private let walkSpeed: CGFloat = 60 // points per second

    init() {
        let texture = PetNode.makePlaceholderTexture()
        stateMachine = PetStateMachine()
        super.init(texture: texture, color: .clear, size: texture.size())
        stateMachine.pet = self
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Placeholder art

    /// Draws a simple rounded blob with two "ears" so there's a recognizable
    /// silhouette on screen before real sprite art exists.
    private static func makePlaceholderTexture() -> SKTexture {
        let size = CGSize(width: 48, height: 40)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.systemOrange.setFill()
        let body = NSBezierPath(ovalIn: NSRect(x: 4, y: 0, width: 40, height: 32))
        body.fill()

        let earLeft = NSBezierPath(ovalIn: NSRect(x: 6, y: 24, width: 12, height: 12))
        let earRight = NSBezierPath(ovalIn: NSRect(x: 30, y: 24, width: 12, height: 12))
        earLeft.fill()
        earRight.fill()

        image.unlockFocus()
        return SKTexture(image: image)
    }

    // MARK: - Actions used by the state machine

    func playIdle() {
        removeAllActions()
        let breathe = SKAction.sequence([
            .scaleY(to: 0.94, duration: 0.6),
            .scaleY(to: 1.0, duration: 0.6)
        ])
        run(.repeatForever(breathe), withKey: "idle")
    }

    func playWalk(toRight: Bool, completion: @escaping () -> Void) {
        removeAllActions()
        xScale = toRight ? abs(xScale) : -abs(xScale)

        let targetX = toRight ? walkableRange.upperBound - size.width / 2
                               : walkableRange.lowerBound + size.width / 2
        let distance = abs(targetX - position.x)
        let duration = TimeInterval(distance / walkSpeed)

        let bob = SKAction.sequence([
            .moveBy(x: 0, y: 4, duration: 0.15),
            .moveBy(x: 0, y: -4, duration: 0.15)
        ])
        let bobbing = SKAction.repeatForever(bob)
        run(bobbing, withKey: "bob")

        let move = SKAction.moveTo(x: targetX, duration: duration)
        run(move, completion: completion)
    }
}

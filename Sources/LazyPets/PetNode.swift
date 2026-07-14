import AppKit
import SpriteKit

/// The pet itself: a pixel-art sprite plus the state machine driving its
/// idle/walk behavior. Frames come from `PetAnimations` (sliced sprite sheets)
/// and are advanced by a fixed-timestep frame stepper, not spring/easing.
final class PetNode: SKSpriteNode {

    let stateMachine: PetStateMachine
    var walkableRange: ClosedRange<CGFloat> = 0...400

    private let walkSpeed: CGFloat = 60 // points per second

    /// Integer scale keeps the pixel art crisp — each source pixel maps to an
    /// N×N block. Combined with `.nearest` filtering there's no bilinear blur.
    private let pixelScale: CGFloat = 2

    init() {
        stateMachine = PetStateMachine()
        let firstFrame = PetAnimations.idle.first
        super.init(
            texture: firstFrame,
            color: .clear,
            size: firstFrame?.size() ?? CGSize(width: 46, height: 55)
        )
        texture?.filteringMode = .nearest

        // Anchor at bottom-center so the feet stay pinned to the Dock even
        // though idle/walk/transition frames have slightly different heights
        // (55 vs 58px) — the baseline never pops between states.
        anchorPoint = CGPoint(x: 0.5, y: 0)
        setScale(pixelScale)

        stateMachine.pet = self
        playIdle()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Actions used by the state machine

    /// Loops the idle strip continuously.
    func playIdle() {
        removeAllActions()
        xScale = pixelScale // face right while resting.

        let loop = SKAction.animate(
            withTextures: PetAnimations.idle,
            timePerFrame: PetAnimations.idleTimePerFrame,
            resize: true,
            restore: false
        )
        run(.repeatForever(loop), withKey: "frames")
    }

    /// Plays the idle→walk transition once, then loops the walk cycle while the
    /// pet crosses the Dock. `completion` fires when it reaches the edge.
    func playWalk(toRight: Bool, completion: @escaping () -> Void) {
        removeAllActions()
        // Sprite art faces right; mirror it (around the center) to walk left.
        xScale = toRight ? pixelScale : -pixelScale

        // Frame stepper: transition once → walk loop forever.
        let transition = SKAction.animate(
            withTextures: PetAnimations.transition,
            timePerFrame: PetAnimations.transitionTimePerFrame,
            resize: true,
            restore: false
        )
        let walkLoop = SKAction.animate(
            withTextures: PetAnimations.walk,
            timePerFrame: PetAnimations.walkTimePerFrame,
            resize: true,
            restore: false
        )
        run(.sequence([transition, .repeatForever(walkLoop)]), withKey: "frames")

        // Movement runs concurrently with the frame stepper. Inset the target
        // by half the sprite's visual width so it doesn't clip off the edge.
        let halfWidth = size.width * pixelScale / 2
        let targetX = toRight
            ? walkableRange.upperBound - halfWidth
            : walkableRange.lowerBound + halfWidth
        let distance = abs(targetX - position.x)
        let duration = TimeInterval(distance / walkSpeed)

        let move = SKAction.moveTo(x: targetX, duration: duration)
        run(.sequence([move, .run(completion)]), withKey: "move")
    }
}

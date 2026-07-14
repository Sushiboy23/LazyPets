import AppKit
import SpriteKit

/// The pet itself: a pixel-art sprite plus the state machine driving its
/// idle/walk behavior. Frames come from `PetAnimations` (sliced sprite sheets)
/// and are advanced by a fixed-timestep frame stepper, not spring/easing.
final class PetNode: SKSpriteNode {

    let stateMachine: PetStateMachine
    var walkableRange: ClosedRange<CGFloat> = 0...400

    private(set) var animations: PetAnimationSet = PetAnimations.set(for: .girl)

    /// The active pet's ground speed (see `PetAnimationSet.walkSpeed`).
    private var walkSpeed: CGFloat { animations.walkSpeed }

    /// The active pet's render scale (see `PetAnimationSet.pixelScale`).
    /// Note: `petHeadroom` in PetOverlayWindow must be at least the tallest
    /// frame height × this scale or the sprite gets clipped by the window edge.
    private var pixelScale: CGFloat { animations.pixelScale }

    init() {
        stateMachine = PetStateMachine()
        let firstFrame = animations.idle.first
        super.init(
            texture: firstFrame,
            color: .clear,
            size: firstFrame?.size() ?? CGSize(width: 46, height: 55)
        )
        texture?.filteringMode = .nearest

        // Anchor at bottom-center so the feet stay pinned to the Dock even
        // though frames have different heights across states and pets — the
        // baseline never pops.
        anchorPoint = CGPoint(x: 0.5, y: 0)
        setScale(pixelScale)

        stateMachine.pet = self
        playIdle()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Pet selection

    var canAttack: Bool { !animations.attacks.isEmpty }

    /// Swaps to another pet's sprite set and restarts behavior from idle.
    func use(_ kind: PetKind) {
        animations = PetAnimations.set(for: kind)
        setScale(pixelScale) // pets render at different scales
        stateMachine.restart()
    }

    /// Mirrors the sprite only when the requested direction differs from the
    /// way the source art natively faces (girl faces left, knight right).
    private func facingScale(toRight: Bool) -> CGFloat {
        toRight == animations.artFacesRight ? pixelScale : -pixelScale
    }

    // MARK: - Actions used by the state machine

    /// Loops the idle strip continuously.
    func playIdle() {
        removeAllActions()
        xScale = pixelScale // unmirrored — the art's native pose while resting.

        let loop = SKAction.animate(
            with: animations.idle,
            timePerFrame: animations.idleTimePerFrame,
            resize: true,
            restore: false
        )
        run(.repeatForever(loop), withKey: "frames")
    }

    /// Plays the idle→walk transition once (if the pet has one), then loops the
    /// walk cycle while crossing the Dock. `completion` fires at the edge.
    func playWalk(toRight: Bool, completion: @escaping () -> Void) {
        removeAllActions()
        xScale = facingScale(toRight: toRight)

        // Frame stepper: optional transition once → walk loop forever.
        let walkLoop = SKAction.animate(
            with: animations.walk,
            timePerFrame: animations.walkTimePerFrame,
            resize: true,
            restore: false
        )
        var steps: [SKAction] = []
        if !animations.walkIn.isEmpty {
            steps.append(.animate(
                with: animations.walkIn,
                timePerFrame: animations.walkInTimePerFrame,
                resize: true,
                restore: false
            ))
        }
        steps.append(.repeatForever(walkLoop))
        run(.sequence(steps), withKey: "frames")

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

    /// Plays one randomly chosen attack variant once, in place, keeping the
    /// current facing. `completion` fires when the swing finishes.
    func playAttack(completion: @escaping () -> Void) {
        guard let attack = animations.attacks.randomElement() else {
            completion()
            return
        }
        removeAllActions()

        let swing = SKAction.animate(
            with: attack,
            timePerFrame: animations.attackTimePerFrame,
            resize: true,
            restore: false
        )
        run(.sequence([swing, .run(completion)]), withKey: "frames")
    }
}

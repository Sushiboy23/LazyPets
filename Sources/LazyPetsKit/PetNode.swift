import AppKit
import SpriteKit

/// The pet itself: a pixel-art sprite plus the state machine driving its
/// idle/walk behavior. Frames come from `PetAnimations` (sliced sprite sheets)
/// and are advanced by a fixed-timestep frame stepper, not spring/easing.
final class PetNode: SKSpriteNode {

    let stateMachine: PetStateMachine
    var walkableRange: ClosedRange<CGFloat> = 0...400

    let kind: PetKind
    let animations: PetAnimationSet

    /// The active pet's ground speed (see `PetAnimationSet.walkSpeed`).
    private var walkSpeed: CGFloat { animations.walkSpeed }

    /// The active pet's render scale (see `PetAnimationSet.pixelScale`).
    /// Note: `petHeadroom` in PetOverlayWindow must be at least the tallest
    /// frame height × this scale or the sprite gets clipped by the window edge.
    private var pixelScale: CGFloat { animations.pixelScale }

    init(kind: PetKind) {
        self.kind = kind
        animations = PetAnimations.set(for: kind)
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

    /// On-screen bounding box of the character's visible pixels — `frame`
    /// includes the art's transparent padding, this doesn't (see
    /// `PetAnimations.bodyUnitRect`). Mirroring flips the body's horizontal
    /// offset within the frame, hence the xScale check.
    var bodyFrame: CGRect {
        let unit = PetAnimations.bodyUnitRect(for: kind)
        let frame = self.frame
        let unitMinX = xScale < 0 ? 1 - unit.maxX : unit.minX
        return CGRect(
            x: frame.minX + unitMinX * frame.width,
            y: frame.minY + unit.minY * frame.height,
            width: unit.width * frame.width,
            height: unit.height * frame.height
        )
    }

    var canAttack: Bool { !animations.attacks.isEmpty }
    var canWalk: Bool { !animations.walk.isEmpty }
    var canRun: Bool { !animations.run.isEmpty }
    var canJump: Bool { !animations.jump.isEmpty }

    /// Ground level captured when a jump starts, so interrupting the hop
    /// mid-air (e.g. an attack) can't leave the pet floating.
    private var groundY: CGFloat?

    private func snapToGround() {
        if let groundY {
            position.y = groundY
            self.groundY = nil
        }
    }

    /// Mirrors the sprite only when the requested direction differs from the
    /// way the source art natively faces (girl faces left, knight right).
    private func facingScale(toRight: Bool) -> CGFloat {
        toRight == animations.artFacesRight ? pixelScale : -pixelScale
    }

    // MARK: - Actions used by the state machine

    /// Loops the idle strip continuously. Pets with `idleVariants` weave one
    /// randomly chosen variant in after a few passes of the main loop, so the
    /// main idle still fills most of the resting time.
    func playIdle() {
        removeAllActions()
        snapToGround()
        xScale = pixelScale // unmirrored — the art's native pose while resting.
        runIdleCycle()
    }

    /// One idle "cycle": several main-loop passes, then (if the pet has any)
    /// a single variant pass, then recurse — re-rolling the pass count and
    /// variant each time so the rhythm doesn't feel mechanical.
    private func runIdleCycle() {
        let mainLoop = SKAction.animate(
            with: animations.idle,
            timePerFrame: animations.idleTimePerFrame,
            resize: true,
            restore: false
        )
        guard let variant = animations.idleVariants.randomElement() else {
            run(.repeatForever(mainLoop), withKey: "frames")
            return
        }
        run(.sequence([
            .repeat(mainLoop, count: Int.random(in: 2...4)),
            .animate(
                with: variant,
                timePerFrame: animations.idleVariantTimePerFrame,
                resize: true,
                restore: false
            ),
            .run { [weak self] in self?.runIdleCycle() },
        ]), withKey: "frames")
    }

    /// Plays the idle→walk transition once (if the pet has one), then loops the
    /// walk cycle while crossing the Dock. `completion` fires at the edge.
    func playWalk(toRight: Bool, completion: @escaping () -> Void) {
        playGait(
            loopFrames: animations.walk,
            timePerFrame: animations.walkTimePerFrame,
            intro: animations.walkIn,
            introTimePerFrame: animations.walkInTimePerFrame,
            speed: walkSpeed,
            toRight: toRight,
            completion: completion
        )
    }

    /// Loops the run cycle while sprinting across the Dock. Only meaningful
    /// for pets where `canRun` is true.
    func playRun(toRight: Bool, completion: @escaping () -> Void) {
        playGait(
            loopFrames: animations.run,
            timePerFrame: animations.runTimePerFrame,
            intro: animations.runIn,
            introTimePerFrame: animations.runInTimePerFrame,
            speed: animations.runSpeed,
            toRight: toRight,
            completion: completion
        )
    }

    /// Shared gait player: optional intro once → loop frames forever, while a
    /// concurrent move action carries the pet toward the Dock edge.
    private func playGait(
        loopFrames: [SKTexture],
        timePerFrame: TimeInterval,
        intro: [SKTexture],
        introTimePerFrame: TimeInterval,
        speed: CGFloat,
        toRight: Bool,
        completion: @escaping () -> Void
    ) {
        removeAllActions()
        snapToGround()
        xScale = facingScale(toRight: toRight)

        let loop = SKAction.animate(
            with: loopFrames,
            timePerFrame: timePerFrame,
            resize: true,
            restore: false
        )
        var steps: [SKAction] = []
        if !intro.isEmpty {
            steps.append(.animate(
                with: intro,
                timePerFrame: introTimePerFrame,
                resize: true,
                restore: false
            ))
        }
        steps.append(.repeatForever(loop))
        run(.sequence(steps), withKey: "frames")

        // Movement runs concurrently with the frame stepper. Inset the target
        // by half the sprite's visual width so it doesn't clip off the edge.
        let halfWidth = size.width * pixelScale / 2
        let targetX = toRight
            ? walkableRange.upperBound - halfWidth
            : walkableRange.lowerBound + halfWidth
        let distance = abs(targetX - position.x)
        let duration = TimeInterval(distance / speed)

        let move = SKAction.moveTo(x: targetX, duration: duration)
        run(.sequence([move, .run(completion)]), withKey: "move")
    }

    /// One in-place hop: jump/fall frames play once while a parabola-ish
    /// up-then-down move runs alongside. Keeps the current facing.
    func playJump(completion: @escaping () -> Void) {
        guard canJump else {
            completion()
            return
        }
        removeAllActions()
        snapToGround()
        groundY = position.y

        let frames = SKAction.animate(
            with: animations.jump,
            timePerFrame: animations.jumpTimePerFrame,
            resize: true,
            restore: false
        )
        run(.sequence([frames, .run(completion)]), withKey: "frames")

        // Split the hop across the animation duration; ease out/in fakes an arc.
        let half = animations.jumpTimePerFrame * Double(animations.jump.count) / 2
        let up = SKAction.moveBy(x: 0, y: 44, duration: half)
        up.timingMode = .easeOut
        let down = SKAction.moveBy(x: 0, y: -44, duration: half)
        down.timingMode = .easeIn
        run(.sequence([up, down]), withKey: "move")
    }

    /// Plays one randomly chosen attack variant once, in place, keeping the
    /// current facing. `completion` fires when the swing finishes.
    func playAttack(completion: @escaping () -> Void) {
        guard let attack = animations.attacks.randomElement() else {
            completion()
            return
        }
        removeAllActions()
        snapToGround()

        let swing = SKAction.animate(
            with: attack,
            timePerFrame: animations.attackTimePerFrame,
            resize: true,
            restore: false
        )
        run(.sequence([swing, .run(completion)]), withKey: "frames")
    }
}

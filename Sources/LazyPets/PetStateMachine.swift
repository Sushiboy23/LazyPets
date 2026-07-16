import Foundation

/// Drives ambient idle/walk behavior with randomized timing so movement
/// doesn't feel mechanical. Deliberately simple (two states, a timer) —
/// this is the seam to extend later for click/drag reactions or a
/// needs-based (hunger/happiness) system.
final class PetStateMachine {

    enum State {
        case idle
        case walking
        case running
        case jumping
        case attacking
    }

    weak var pet: PetNode?

    private(set) var state: State = .idle
    private var timer: Timer?

    /// While true the pet never roams — it stays planted where it is, still
    /// animating its idle loop (the timer feature's "focused" stance).
    /// Jumps and attacks are in place, so they may still occur/finish.
    private(set) var holdsPosition = false

    private let idleDurationRange: ClosedRange<Double> = 4...12
    private let walkDurationRange: ClosedRange<Double> = 3...8

    func start() {
        enterIdle()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Re-enters idle immediately — used after swapping pets so the new
    /// sprite set starts from a clean state.
    func restart() {
        enterIdle()
    }

    /// Interrupts whatever the pet is doing to play one random attack
    /// animation, then falls back to idle. No-op for pets without attacks
    /// (`then` is not called in that case — don't hang side effects on it).
    /// - Parameter then: runs after the swing finishes, e.g. trashing a
    ///   dropped file once the pet has "attacked" it.
    func triggerAttack(then: (() -> Void)? = nil) {
        guard let pet, pet.canAttack else { return }
        timer?.invalidate()
        state = .attacking
        pet.playAttack { [weak self] in
            self?.enterIdle()
            then?()
        }
    }

    func setHoldsPosition(_ holds: Bool) {
        holdsPosition = holds
        if holds, state == .walking || state == .running {
            enterIdle() // stop mid-stride; the pet plants where it stands
        }
    }

    /// One-shot celebration for a finished timer: a hop for pets that can
    /// jump, an attack swing otherwise, then back to idle.
    func triggerCelebration() {
        guard let pet else { return }
        if pet.canJump {
            timer?.invalidate()
            state = .jumping
            pet.playJump { [weak self] in
                self?.enterIdle()
            }
        } else if pet.canAttack {
            triggerAttack()
        }
    }

    private func enterIdle() {
        state = .idle
        pet?.playIdle()
        scheduleNext(after: Double.random(in: idleDurationRange)) { [weak self] in
            self?.pickNextActivity()
        }
    }

    /// After resting, pets that can jump or run sometimes do; most rolls walk.
    /// Pets without a walk animation (samurai) always run instead.
    private func pickNextActivity() {
        guard let pet else { return }
        if holdsPosition {
            enterIdle() // focused pets just keep idling in place
            return
        }
        let roll = Double.random(in: 0..<1)
        if pet.canJump && roll < 0.2 {
            enterJump()
        } else if pet.canRun && (roll < 0.5 || !pet.canWalk) {
            enterRun()
        } else if pet.canWalk {
            enterWalk()
        } else {
            // No gaits at all — just keep idling.
            enterIdle()
        }
    }

    private func enterWalk() {
        state = .walking
        let toRight = Bool.random()
        pet?.playWalk(toRight: toRight) { [weak self] in
            // Reached the edge before the walk timer expired — go idle immediately.
            self?.enterIdle()
        }
        scheduleNext(after: Double.random(in: walkDurationRange)) { [weak self] in
            // Walk "timed out" while still mid-stride; let the current move
            // action finish naturally and fall back to idle after it does.
            self?.enterIdle()
        }
    }

    private func enterRun() {
        state = .running
        let toRight = Bool.random()
        pet?.playRun(toRight: toRight) { [weak self] in
            self?.enterIdle()
        }
        // Runs cover ground fast; keep the burst short.
        scheduleNext(after: Double.random(in: 1.5...4)) { [weak self] in
            self?.enterIdle()
        }
    }

    private func enterJump() {
        state = .jumping
        timer?.invalidate()
        pet?.playJump { [weak self] in
            self?.enterIdle()
        }
    }

    private func scheduleNext(after seconds: Double, action: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            action()
        }
    }
}

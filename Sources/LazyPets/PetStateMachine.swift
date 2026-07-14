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
    /// animation, then falls back to idle. No-op for pets without attacks.
    func triggerAttack() {
        guard let pet, pet.canAttack else { return }
        timer?.invalidate()
        state = .attacking
        pet.playAttack { [weak self] in
            self?.enterIdle()
        }
    }

    private func enterIdle() {
        state = .idle
        pet?.playIdle()
        scheduleNext(after: Double.random(in: idleDurationRange)) { [weak self] in
            self?.pickNextActivity()
        }
    }

    /// After resting, pets that can jump or run sometimes do; everyone else
    /// (and most rolls) just walks.
    private func pickNextActivity() {
        guard let pet else { return }
        let roll = Double.random(in: 0..<1)
        if pet.canJump && roll < 0.2 {
            enterJump()
        } else if pet.canRun && roll < 0.5 {
            enterRun()
        } else {
            enterWalk()
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

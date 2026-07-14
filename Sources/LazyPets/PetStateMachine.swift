import Foundation

/// Drives ambient idle/walk behavior with randomized timing so movement
/// doesn't feel mechanical. Deliberately simple (two states, a timer) —
/// this is the seam to extend later for click/drag reactions or a
/// needs-based (hunger/happiness) system.
final class PetStateMachine {

    enum State {
        case idle
        case walking
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
            self?.enterWalk()
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

    private func scheduleNext(after seconds: Double, action: @escaping () -> Void) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            action()
        }
    }
}

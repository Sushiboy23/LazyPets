import Foundation

/// One pet's countdown timer. `endsAt` is an absolute timestamp — not a
/// decrementing counter — so timers survive relaunch and sleep without
/// drifting. `duration` is the originally chosen length; "add 5 minutes"
/// pushes `endsAt` out but leaves `duration` alone, so "restart same timer"
/// means the length the user first picked.
///
/// Persistence is keyed by `PetKind`, not the pet's instance UUID: instance
/// ids are regenerated every launch, and each kind appears on the Dock at
/// most once, so kind is the stable identity. A pet with no entry is idle.
struct PetTimerState: Codable {
    enum Status: String, Codable {
        case running
        case done
    }

    var note: String
    var startedAt: Date
    var endsAt: Date
    var duration: TimeInterval
    var status: Status

    var remaining: TimeInterval { endsAt.timeIntervalSinceNow }

    /// "25:00" / "1:05:00" style countdown text.
    static func format(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }
}

/// Owns every pet's timer: mutations, the shared 1-second tick, completion
/// detection, and persistence. Timers are fully independent per pet — there
/// is no single-timer assumption anywhere. AppDelegate injects the side
/// effects (badges, notifications, sounds) through the callbacks.
final class PetTimerManager {

    private(set) var timers: [PetKind: PetTimerState] = [:]

    /// Fires once per second per running timer — drives the progress ring.
    var onTick: ((PetKind, PetTimerState) -> Void)?
    /// A running timer reached zero; status is already `.done`.
    var onCompleted: ((PetKind, PetTimerState) -> Void)?
    /// Any other lifecycle change: started, extended, snoozed, cancelled, or
    /// dismissed (`nil` state once cleared). Note edits don't fire this.
    var onChanged: ((PetKind, PetTimerState?) -> Void)?

    private var ticker: Timer?
    private static let defaultsKey = "petTimers"

    // MARK: - Lifecycle

    /// Restores persisted timers and settles them against the current time:
    /// timers that expired while the app wasn't running complete immediately
    /// (notification, animation and all) instead of staying silently frozen;
    /// still-running ones resume; unacknowledged done ones re-show as done.
    func loadAndReconcile() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode([String: PetTimerState].self, from: data) {
            for (raw, state) in stored {
                guard let kind = PetKind(rawValue: raw) else { continue }
                timers[kind] = state
            }
        }
        for (kind, state) in timers {
            switch state.status {
            case .running where state.remaining <= 0:
                complete(kind)
            case .running, .done:
                onChanged?(kind, state)
            }
        }
        syncTicker()
    }

    func start(kind: PetKind, seconds: Int, note: String) {
        let now = Date()
        let duration = TimeInterval(seconds)
        let state = PetTimerState(
            note: note,
            startedAt: now,
            endsAt: now.addingTimeInterval(duration),
            duration: duration,
            status: .running
        )
        timers[kind] = state
        save()
        syncTicker()
        onChanged?(kind, state)
    }

    func addMinutes(_ minutes: Int, for kind: PetKind) {
        guard var state = timers[kind], state.status == .running else { return }
        state.endsAt.addTimeInterval(TimeInterval(minutes * 60))
        timers[kind] = state
        save()
        onChanged?(kind, state)
    }

    /// Saved immediately — the popover edits notes inline with no confirm.
    func updateNote(_ note: String, for kind: PetKind) {
        guard var state = timers[kind] else { return }
        state.note = note
        timers[kind] = state
        save()
    }

    func cancel(kind: PetKind) {
        clear(kind)
    }

    /// Acknowledges a done timer and returns the pet to idle.
    func dismissDone(kind: PetKind) {
        clear(kind)
    }

    /// Done → running again with the original duration and note.
    func restart(kind: PetKind) {
        guard let old = timers[kind] else { return }
        start(kind: kind, seconds: max(1, Int(old.duration)), note: old.note)
    }

    /// Done → running for a short extension (the notification's snooze).
    func snooze(kind: PetKind, minutes: Int = 5) {
        guard var state = timers[kind], state.status == .done else { return }
        state.status = .running
        state.endsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        timers[kind] = state
        save()
        syncTicker()
        onChanged?(kind, state)
    }

    // MARK: - Internals

    private func clear(_ kind: PetKind) {
        guard timers.removeValue(forKey: kind) != nil else { return }
        save()
        syncTicker()
        onChanged?(kind, nil)
    }

    private func complete(_ kind: PetKind) {
        guard var state = timers[kind] else { return }
        state.status = .done
        timers[kind] = state
        save()
        syncTicker()
        onCompleted?(kind, state)
    }

    private func tick() {
        for (kind, state) in timers where state.status == .running {
            if state.remaining <= 0 {
                complete(kind)
            } else {
                onTick?(kind, state)
            }
        }
    }

    /// The ticker exists only while something is actually counting down —
    /// idle costs nothing, in keeping with the rest of the app.
    private func syncTicker() {
        let anyRunning = timers.values.contains { $0.status == .running }
        if anyRunning && ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                self?.tick()
            }
        } else if !anyRunning {
            ticker?.invalidate()
            ticker = nil
        }
    }

    private func save() {
        let stored = Dictionary(uniqueKeysWithValues: timers.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

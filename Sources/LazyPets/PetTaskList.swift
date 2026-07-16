import Foundation

/// One entry in a pet's Task List. Tasks are deliberately not day-scoped:
/// nothing ever clears or resets them — they live until the user edits or
/// deletes them.
struct PetTask: Codable, Identifiable {
    let id: UUID
    var text: String
    var isDone: Bool
    let createdAt: Date

    init(text: String) {
        id = UUID()
        self.text = text
        isDone = false
        createdAt = Date()
    }
}

/// Owns every pet's Task List and persists each mutation immediately.
/// Keyed by `PetKind` for the same reason as the timers: instance UUIDs are
/// regenerated every launch, kind is the stable identity.
final class PetTaskStore: ObservableObject {

    @Published private(set) var tasksByKind: [PetKind: [PetTask]] = [:]

    private static let defaultsKey = "petTaskLists"

    init() {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
              let stored = try? JSONDecoder().decode([String: [PetTask]].self, from: data) else {
            return
        }
        for (raw, tasks) in stored {
            guard let kind = PetKind(rawValue: raw) else { continue }
            tasksByKind[kind] = tasks
        }
    }

    func tasks(for kind: PetKind) -> [PetTask] {
        tasksByKind[kind] ?? []
    }

    func add(_ text: String, for kind: PetKind) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tasksByKind[kind, default: []].append(PetTask(text: trimmed))
        save()
    }

    func setText(_ text: String, taskID: UUID, for kind: PetKind) {
        mutate(taskID, for: kind) { $0.text = text }
    }

    func setDone(_ done: Bool, taskID: UUID, for kind: PetKind) {
        mutate(taskID, for: kind) { $0.isDone = done }
    }

    func delete(taskID: UUID, for kind: PetKind) {
        tasksByKind[kind]?.removeAll { $0.id == taskID }
        save()
    }

    private func mutate(_ taskID: UUID, for kind: PetKind, _ change: (inout PetTask) -> Void) {
        guard var tasks = tasksByKind[kind],
              let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        change(&tasks[index])
        tasksByKind[kind] = tasks
        save()
    }

    private func save() {
        let stored = Dictionary(uniqueKeysWithValues: tasksByKind.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

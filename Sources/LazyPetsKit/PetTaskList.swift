import Foundation

/// One entry in the Task List. Tasks are deliberately not day-scoped:
/// nothing ever clears or resets them — they live until the user edits or
/// deletes them.
/// What the date shown on a task row represents.
enum TaskDateKind: String, Codable {
    /// The editable due date ("Due 22 Jul", red when overdue).
    case completeBy
    /// The task's automatic creation date ("Added 15 Jul").
    case createdOn
    /// No date on the row — the due and created dates are kept, just not shown.
    case hidden
}

struct PetTask: Codable, Identifiable {
    let id: UUID
    var text: String
    var isDone: Bool
    /// Hidden tasks stay in the list (and the manage window) but are
    /// filtered out of the pet-click popover.
    var isHiddenInPopover: Bool
    /// Optional "complete by" day (normalized to start of day; nil = none).
    var dueDate: Date?
    /// Which date the row displays for this task.
    var dateKind: TaskDateKind
    /// Set automatically when the task is added, but user-editable.
    var createdAt: Date

    init(text: String) {
        id = UUID()
        self.text = text
        isDone = false
        isHiddenInPopover = false
        dueDate = nil
        dateKind = .completeBy
        createdAt = Date()
    }

    // Custom decoding so tasks saved before the hide/due-date features
    // (missing those keys) still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        isDone = try container.decode(Bool.self, forKey: .isDone)
        isHiddenInPopover = try container.decodeIfPresent(Bool.self, forKey: .isHiddenInPopover) ?? false
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        dateKind = try container.decodeIfPresent(TaskDateKind.self, forKey: .dateKind) ?? .completeBy
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    /// Due day fully passed without the task being done.
    var isOverdue: Bool {
        guard let dueDate, !isDone else { return false }
        return dueDate < Calendar.current.startOfDay(for: Date())
    }
}

/// Owns the single shared Task List (every pet opens the same one) and
/// persists each mutation immediately.
final class PetTaskStore: ObservableObject {

    @Published private(set) var tasks: [PetTask] = []

    private static let defaultsKey = "sharedTaskList"
    /// The pre-centralization format: one list per pet kind.
    private static let legacyPerPetKey = "petTaskLists"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let stored = try? JSONDecoder().decode([PetTask].self, from: data) {
            tasks = stored
            return
        }
        // One-time migration: merge the old per-pet lists, oldest task first.
        if let data = UserDefaults.standard.data(forKey: Self.legacyPerPetKey),
           let stored = try? JSONDecoder().decode([String: [PetTask]].self, from: data) {
            tasks = stored.values.flatMap { $0 }.sorted { $0.createdAt < $1.createdAt }
            save()
            UserDefaults.standard.removeObject(forKey: Self.legacyPerPetKey)
        }
    }

    func add(_ text: String, dueDate: Date? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var task = PetTask(text: trimmed)
        task.dueDate = dueDate.map { Calendar.current.startOfDay(for: $0) }
        tasks.append(task)
        save()
    }

    func setText(_ text: String, taskID: UUID) {
        mutate(taskID) { $0.text = text }
    }

    func setDone(_ done: Bool, taskID: UUID) {
        mutate(taskID) { $0.isDone = done }
    }

    func setHiddenInPopover(_ hidden: Bool, taskID: UUID) {
        mutate(taskID) { $0.isHiddenInPopover = hidden }
    }

    /// nil clears the due date. Dates are normalized to start of day so
    /// overdue checks compare whole days, not times.
    func setDueDate(_ date: Date?, taskID: UUID) {
        mutate(taskID) { $0.dueDate = date.map { Calendar.current.startOfDay(for: $0) } }
    }

    func setDateKind(_ kind: TaskDateKind, taskID: UUID) {
        mutate(taskID) { $0.dateKind = kind }
    }

    func setCreatedAt(_ date: Date, taskID: UUID) {
        mutate(taskID) { $0.createdAt = date }
    }

    func delete(taskID: UUID) {
        tasks.removeAll { $0.id == taskID }
        save()
    }

    private func mutate(_ taskID: UUID, _ change: (inout PetTask) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        change(&tasks[index])
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

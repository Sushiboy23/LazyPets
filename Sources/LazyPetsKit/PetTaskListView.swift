import SwiftUI

/// The shared Task List panel — every pet opens this same list: checkable
/// rows with inline text editing, per-row delete, and an add field. Every
/// change persists immediately through the store.
struct PetTaskListView: View {

    @ObservedObject var store: PetTaskStore
    /// Hidden when the panel sits under the Timer/Task List tab switcher,
    /// which already names it.
    var showsHeader = true
    /// When set, a "Manage tasks…" button appears that hands off to the
    /// manage window's Task list page (popover use only).
    var onManageTasks: (() -> Void)?
    /// The popover uses a fixed compact width; the manage window lets the
    /// panel stretch.
    var popoverLayout = true
    /// Manage-window mode: shows every task (hidden ones dimmed) with a
    /// per-row eye toggle. When false (popover), hidden tasks are filtered
    /// out entirely.
    var managesHiddenTasks = false

    @State private var newTaskText = ""
    /// Due date staged for the task being typed; applied on add, then cleared.
    @State private var newTaskDueDate: Date?
    @State private var showsNewTaskDatePicker = false
    /// Task whose due-date picker popover is currently open.
    @State private var dueDatePickerTaskID: UUID?

    private let rowHeight: CGFloat = 26

    private static let dueDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                Label("Task List", systemImage: "checklist")
                    .font(.headline)
            }

            let tasks = managesHiddenTasks
                ? store.tasks
                : store.tasks.filter { !$0.isHiddenInPopover }
            if tasks.isEmpty {
                Text(store.tasks.isEmpty ? "No tasks yet." : "All tasks are hidden.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(tasks) { task in
                            row(for: task)
                        }
                    }
                }
                // A fixed (not max) height: a flexible ScrollView would let
                // the popover keep the smaller Timer-tab size after a tab
                // switch instead of growing back.
                .frame(height: min(CGFloat(tasks.count) * rowHeight, 220))
            }

            HStack(spacing: 6) {
                TextField("Add a task…", text: $newTaskText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTask)
                newTaskDueDateControl
                Button(action: addTask) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let onManageTasks {
                Button("Manage tasks…", action: onManageTasks)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(popoverLayout ? 12 : 0)
        .frame(width: popoverLayout ? 260 : nil)
    }

    private func addTask() {
        store.add(newTaskText, dueDate: newTaskDueDate)
        newTaskText = ""
        newTaskDueDate = nil
    }

    /// Same calendar affordance as task rows, but staging the date for the
    /// task about to be created.
    private var newTaskDueDateControl: some View {
        Button {
            showsNewTaskDatePicker = true
        } label: {
            if let due = newTaskDueDate {
                Text("Due \(Self.dueDateFormatter.string(from: due))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.secondary)
            } else {
                Image(systemName: "calendar")
                    .foregroundStyle(Color(.tertiaryLabelColor))
            }
        }
        .buttonStyle(.plain)
        .help(newTaskDueDate == nil ? "Add a due date to the new task" : "Change the new task's due date")
        .popover(isPresented: $showsNewTaskDatePicker) {
            VStack(spacing: 8) {
                DatePicker(
                    "Due date",
                    selection: Binding(
                        get: { newTaskDueDate ?? Date() },
                        set: { newTaskDueDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                if newTaskDueDate != nil {
                    Button("Remove due date") {
                        newTaskDueDate = nil
                        showsNewTaskDatePicker = false
                    }
                    .controlSize(.small)
                }
            }
            .padding(10)
            .frame(width: 180)
        }
    }

    private func row(for task: PetTask) -> some View {
        HStack(spacing: 6) {
            Button {
                store.setDone(!task.isDone, taskID: task.id)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            // Done tasks render as Text because TextField ignores
            // .strikethrough on macOS; untick to edit again.
            if task.isDone {
                Text(task.text)
                    .strikethrough()
                    .foregroundStyle(Color.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("", text: textBinding(for: task))
                    .textFieldStyle(.plain)
            }

            dueDateControl(for: task)

            if managesHiddenTasks {
                Button {
                    store.setHiddenInPopover(!task.isHiddenInPopover, taskID: task.id)
                } label: {
                    Image(systemName: task.isHiddenInPopover ? "eye.slash" : "eye")
                        .foregroundStyle(task.isHiddenInPopover ? Color.secondary : Color(.tertiaryLabelColor))
                }
                .buttonStyle(.plain)
                .help(task.isHiddenInPopover ? "Show in the pet popover" : "Hide from the pet popover")
            }

            Button {
                store.delete(taskID: task.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.quaternary)
            }
            .buttonStyle(.plain)
            .help("Delete task")
        }
        .padding(.vertical, 2)
        .opacity(managesHiddenTasks && task.isHiddenInPopover ? 0.5 : 1)
    }

    /// Date affordance, labeled so its meaning is unambiguous: "Due 22 Jul"
    /// (red when overdue), "Added 15 Jul", or a bare calendar icon when the
    /// task shows a due date but none is set. Opens the picker popover.
    private func dueDateControl(for task: PetTask) -> some View {
        Button {
            dueDatePickerTaskID = task.id
        } label: {
            switch task.dateKind {
            case .createdOn:
                Text("Added \(Self.dueDateFormatter.string(from: task.createdAt))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.secondary)
            case .completeBy:
                if let due = task.dueDate {
                    Text("Due \(Self.dueDateFormatter.string(from: due))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                } else {
                    Image(systemName: "calendar")
                        .foregroundStyle(Color(.tertiaryLabelColor))
                }
            case .hidden:
                // Bare icon keeps the popover reachable while showing no date.
                Image(systemName: "calendar")
                    .foregroundStyle(Color(.tertiaryLabelColor))
            }
        }
        .buttonStyle(.plain)
        .help("Task date")
        .popover(isPresented: Binding(
            get: { dueDatePickerTaskID == task.id },
            set: { if !$0 { dueDatePickerTaskID = nil } }
        )) {
            dueDatePopover(for: task)
        }
    }

    private func dueDatePopover(for task: PetTask) -> some View {
        // Read fresh from the store — `task` is a snapshot from when the
        // popover opened.
        let current = store.tasks.first(where: { $0.id == task.id }) ?? task
        return VStack(spacing: 8) {
            Picker("", selection: Binding(
                get: { current.dateKind },
                set: { store.setDateKind($0, taskID: task.id) }
            )) {
                Text("Complete by").tag(TaskDateKind.completeBy)
                Text("Created on").tag(TaskDateKind.createdOn)
                Text("Hidden").tag(TaskDateKind.hidden)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch current.dateKind {
            case .completeBy:
                DatePicker(
                    "Due date",
                    selection: Binding(
                        get: { current.dueDate ?? Date() },
                        set: { store.setDueDate($0, taskID: task.id) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
                if current.dueDate != nil {
                    Button("Remove due date") {
                        store.setDueDate(nil, taskID: task.id)
                        dueDatePickerTaskID = nil
                    }
                    .controlSize(.small)
                }
            case .createdOn:
                DatePicker(
                    "Created on",
                    selection: Binding(
                        get: { current.createdAt },
                        set: { store.setCreatedAt($0, taskID: task.id) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .labelsHidden()
            case .hidden:
                Text("Dates are kept but not shown on the task.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        // No fixed width — the segmented control decides the natural size;
        // a hard-coded frame clipped its three labels.
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Inline edits write straight through to the store (saved immediately).
    private func textBinding(for task: PetTask) -> Binding<String> {
        Binding(
            get: { store.tasks.first(where: { $0.id == task.id })?.text ?? task.text },
            set: { store.setText($0, taskID: task.id) }
        )
    }
}

/// What a pet click opens: the Timer, Task List, and/or Boombox panels —
/// a segmented switcher appears whenever more than one is enabled.
struct PetClickPopoverView: View {

    // String raw values are the persistence key for "last used tab" — stable,
    // don't rename.
    enum Tab: String {
        case timer
        case tasks
        case boombox
        case dial

        var title: String {
            switch self {
            case .timer: return "Timer"
            case .tasks: return "Task List"
            case .boombox: return "Boombox"
            case .dial: return "Dial"
            }
        }
    }

    let timerModel: TimerPopoverModel? // nil = timer feature off for this pet
    @ObservedObject var taskStore: PetTaskStore
    let showsTasks: Bool
    let boombox: BoomboxController?    // nil = Boombox feature off for this pet
    /// Whether this pet has Dial enabled. The Dial tab is always in the
    /// strip (never silently hidden); when false it leads to an explanatory
    /// disabled state instead of the panel.
    let dialEnabled: Bool
    let audioService: AudioDeviceService
    let levelMonitor: AudioLevelMonitor
    var onManageTasks: (() -> Void)?
    /// Reports user tab switches so the opener can remember the last used tab.
    var onTabChange: ((Tab) -> Void)?

    @State var tab: Tab

    private var tabs: [Tab] {
        var tabs: [Tab] = []
        if timerModel != nil { tabs.append(.timer) }
        if showsTasks { tabs.append(.tasks) }
        if boombox != nil { tabs.append(.boombox) }
        tabs.append(.dial)
        return tabs
    }

    var body: some View {
        let tabs = self.tabs
        VStack(spacing: 0) {
            if tabs.count > 1 {
                Picker("", selection: $tab) {
                    ForEach(tabs, id: \.self) { tab in
                        Text(tab.title)
                            .foregroundStyle(tab == .dial && !dialEnabled ? Color.secondary : Color.primary)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .onChange(of: tab) { newTab in
                    onTabChange?(newTab)
                }
            }

            // Single-panel case shows its own header; tabbed panels don't
            // repeat the name the switcher already shows.
            switch tabs.contains(tab) ? tab : (tabs.first ?? .tasks) {
            case .timer:
                if let timerModel { TimerPopoverView(model: timerModel) }
            case .tasks:
                PetTaskListView(store: taskStore, showsHeader: tabs.count == 1, onManageTasks: onManageTasks)
            case .boombox:
                if let boombox { BoomboxView(controller: boombox, showsHeader: tabs.count == 1) }
            case .dial:
                if dialEnabled {
                    DialPanelView(audio: audioService, levels: levelMonitor, showsHeader: tabs.count == 1)
                } else {
                    DialDisabledView()
                }
            }
        }
    }
}

#Preview("Task List") {
    PetTaskListView(store: PetTaskStore())
}

import SwiftUI

/// The Task List panel for one pet: checkable rows with inline text editing,
/// per-row delete, and an add field. Every change persists immediately
/// through the store.
struct PetTaskListView: View {

    @ObservedObject var store: PetTaskStore
    let kind: PetKind
    /// Hidden when the panel sits under the Timer/Task List tab switcher,
    /// which already names it.
    var showsHeader = true

    @State private var newTaskText = ""

    private let rowHeight: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsHeader {
                Label("Task List", systemImage: "checklist")
                    .font(.headline)
            }

            let tasks = store.tasks(for: kind)
            if tasks.isEmpty {
                Text("No tasks yet.")
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
                Button(action: addTask) {
                    Image(systemName: "plus.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newTaskText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    private func addTask() {
        store.add(newTaskText, for: kind)
        newTaskText = ""
    }

    private func row(for task: PetTask) -> some View {
        HStack(spacing: 6) {
            Button {
                store.setDone(!task.isDone, taskID: task.id, for: kind)
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            TextField("", text: textBinding(for: task))
                .textFieldStyle(.plain)
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? Color.secondary : Color.primary)

            Button {
                store.delete(taskID: task.id, for: kind)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.quaternary)
            }
            .buttonStyle(.plain)
            .help("Delete task")
        }
        .padding(.vertical, 2)
    }

    /// Inline edits write straight through to the store (saved immediately).
    private func textBinding(for task: PetTask) -> Binding<String> {
        Binding(
            get: { store.tasks(for: kind).first(where: { $0.id == task.id })?.text ?? task.text },
            set: { store.setText($0, taskID: task.id, for: kind) }
        )
    }
}

/// What a pet click opens: the Timer panel, the Task List panel, or — when
/// both features are enabled for the pet — a segmented switcher between them.
struct PetClickPopoverView: View {

    enum Tab {
        case timer
        case tasks
    }

    let timerModel: TimerPopoverModel? // nil = timer feature off for this pet
    @ObservedObject var taskStore: PetTaskStore
    let kind: PetKind
    let showsTasks: Bool

    @State var tab: Tab

    var body: some View {
        VStack(spacing: 0) {
            if let timerModel, showsTasks {
                Picker("", selection: $tab) {
                    Text("Timer").tag(Tab.timer)
                    Text("Task List").tag(Tab.tasks)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.top, 10)

                switch tab {
                case .timer: TimerPopoverView(model: timerModel)
                case .tasks: PetTaskListView(store: taskStore, kind: kind, showsHeader: false)
                }
            } else if let timerModel {
                TimerPopoverView(model: timerModel)
            } else {
                PetTaskListView(store: taskStore, kind: kind)
            }
        }
    }
}

#Preview("Task List") {
    PetTaskListView(store: PetTaskStore(), kind: .cat)
}

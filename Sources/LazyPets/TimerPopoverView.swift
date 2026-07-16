import SwiftUI

/// State + callbacks for the per-pet timer popover. AppDelegate owns it and
/// injects the side effects, mirroring how PetRosterModel works.
final class TimerPopoverModel: ObservableObject {

    enum Mode {
        case set        // no timer yet — pick duration + note, start
        case running    // countdown; edit note, add time, cancel
        case done       // finished; restart same timer or dismiss
    }

    let kind: PetKind
    @Published var mode: Mode
    @Published var note: String
    @Published var endsAt: Date

    var onStart: ((Int, String) -> Void)?
    var onAddMinutes: ((Int) -> Void)?
    var onNoteEdited: ((String) -> Void)?
    var onCancelTimer: (() -> Void)?
    var onRestart: (() -> Void)?
    var onDismissDone: (() -> Void)?

    init(kind: PetKind, state: PetTimerState?) {
        self.kind = kind
        note = state?.note ?? ""
        endsAt = state?.endsAt ?? Date()
        switch state?.status {
        case .running: mode = .running
        case .done: mode = .done
        case nil: mode = .set
        }
    }
}

/// Speech-bubble-sized popover shown just above a clicked pet. The mode is
/// derived from the pet's timer state, so a running timer can only be
/// edited/extended/cancelled — never doubled up.
struct TimerPopoverView: View {

    @ObservedObject var model: TimerPopoverModel

    @State private var selectedMinutes: Int?
    @State private var customMinutesText = ""
    @State private var showsCustomField = false

    private static let presets = [5, 15, 25, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch model.mode {
            case .set: setBody
            case .running: runningBody
            case .done: doneBody
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    // MARK: - Set

    private var chosenMinutes: Int? {
        if showsCustomField {
            guard let minutes = Int(customMinutesText), minutes > 0 else { return nil }
            return minutes
        }
        return selectedMinutes
    }

    @ViewBuilder private var setBody: some View {
        Label("Set a timer", systemImage: "timer")
            .font(.headline)
        HStack(spacing: 5) {
            ForEach(Self.presets, id: \.self) { minutes in
                chip("\(minutes)", isOn: !showsCustomField && selectedMinutes == minutes) {
                    selectedMinutes = minutes
                    showsCustomField = false
                }
            }
            chip("Custom", isOn: showsCustomField) {
                showsCustomField = true
            }
        }
        if showsCustomField {
            TextField("Minutes", text: $customMinutesText)
                .textFieldStyle(.roundedBorder)
                .onSubmit(startIfPossible)
        }
        TextField("What are you working on?", text: $model.note)
            .textFieldStyle(.roundedBorder)
            .onSubmit(startIfPossible)
        HStack {
            Spacer()
            Button("Start", action: startIfPossible)
                .keyboardShortcut(.defaultAction)
                .disabled(chosenMinutes == nil)
        }
    }

    private func startIfPossible() {
        guard let minutes = chosenMinutes else { return }
        model.onStart?(minutes, model.note)
    }

    private func chip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium).monospacedDigit())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.18), in: Capsule())
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Running

    @ViewBuilder private var runningBody: some View {
        Label("\(model.kind.rawValue) is focused", systemImage: "timer")
            .font(.headline)
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(PetTimerState.format(model.endsAt.timeIntervalSince(context.date)))
                .font(.title2.weight(.semibold).monospacedDigit())
        }
        TextField("What are you working on?", text: $model.note)
            .textFieldStyle(.roundedBorder)
            .onChange(of: model.note) { newValue in
                model.onNoteEdited?(newValue) // saves immediately, no confirm
            }
        HStack {
            Button("+5 min") { model.onAddMinutes?(5) }
            Button("+10 min") { model.onAddMinutes?(10) }
            Spacer()
            Button("Cancel", role: .destructive) { model.onCancelTimer?() }
        }
        .controlSize(.small)
    }

    // MARK: - Done

    @ViewBuilder private var doneBody: some View {
        Label("Time's up!", systemImage: "alarm.fill")
            .font(.headline)
            .foregroundStyle(.orange)
        if !model.note.isEmpty {
            Text(model.note)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        HStack {
            Button("Restart Same Timer") { model.onRestart?() }
            Spacer()
            Button("Dismiss") { model.onDismissDone?() }
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.small)
    }
}

#Preview("Set") {
    TimerPopoverView(model: TimerPopoverModel(kind: .cat, state: nil))
}

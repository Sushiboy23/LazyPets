import SwiftUI

/// View model backing the status-item popover. AppDelegate owns it, injects
/// the side effects (adding/removing pets on the Dock, attacks, persistence),
/// and SwiftUI observes it.
final class PetRosterModel: ObservableObject {

    @Published var enabledKinds: Set<PetKind>
    /// Pets that "attack" files dropped on them (moving the file to the Trash).
    @Published var attacksFiles: Set<PetKind>
    /// Pets that open the focus-timer popover when clicked on the Dock.
    @Published var timerPets: Set<PetKind>
    @Published var allHidden: Bool = false
    @Published var timerSoundsOn: Bool = true

    var onToggle: ((PetKind, Bool) -> Void)?
    var onAttack: ((PetKind) -> Void)?
    var onAttacksFilesToggle: ((PetKind, Bool) -> Void)?
    var onTimerToggle: ((PetKind, Bool) -> Void)?
    var onTimerSoundsToggle: ((Bool) -> Void)?
    var onHideAll: ((Bool) -> Void)?
    var onQuit: (() -> Void)?

    init(
        enabledKinds: Set<PetKind> = [],
        attacksFiles: Set<PetKind> = [],
        timerPets: Set<PetKind> = []
    ) {
        self.enabledKinds = enabledKinds
        self.attacksFiles = attacksFiles
        self.timerPets = timerPets
    }

    func setEnabled(_ enabled: Bool, for kind: PetKind) {
        if enabled {
            enabledKinds.insert(kind)
        } else {
            enabledKinds.remove(kind)
        }
        onToggle?(kind, enabled)
    }

    func setAttacksFiles(_ on: Bool, for kind: PetKind) {
        if on {
            attacksFiles.insert(kind)
        } else {
            attacksFiles.remove(kind)
        }
        onAttacksFilesToggle?(kind, on)
    }

    func setTimerEnabled(_ on: Bool, for kind: PetKind) {
        if on {
            timerPets.insert(kind)
        } else {
            timerPets.remove(kind)
        }
        onTimerToggle?(kind, on)
    }
}

/// Popover content: one row per pet with avatar, name, optional attack button,
/// and an enable toggle; then a hide-all toggle and a quit button.
struct PetRosterView: View {

    @ObservedObject var model: PetRosterModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("LazyPets", systemImage: "pawprint.fill")
                .font(.headline)

            ForEach(PetKind.allCases, id: \.rawValue) { kind in
                petRow(for: kind)
            }

            Divider()

            Toggle("Hide all pets", isOn: hideAllBinding)
                .toggleStyle(.switch)
                .controlSize(.small)

            Toggle("Timer sounds", isOn: timerSoundsBinding)
                .toggleStyle(.switch)
                .controlSize(.small)

            Button {
                model.onQuit?()
            } label: {
                Text("Quit LazyPets")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    private func petRow(for kind: PetKind) -> some View {
        HStack(spacing: 8) {
            avatar(for: kind)
            Text(kind.rawValue)
            Spacer()
            if !PetAnimations.set(for: kind).attacks.isEmpty {
                Button {
                    model.onAttack?(kind)
                } label: {
                    Image(systemName: "figure.fencing")
                }
                .help("Attack!")
                .disabled(!model.enabledKinds.contains(kind) || model.allHidden)

                Toggle(isOn: attacksFilesBinding(for: kind)) {
                    Image(systemName: "trash")
                }
                .toggleStyle(.button)
                .help("Drop a file on this pet to attack it into the Trash")
                .disabled(!model.enabledKinds.contains(kind))
            }
            Toggle(isOn: timerBinding(for: kind)) {
                Image(systemName: "timer")
            }
            .toggleStyle(.button)
            .help("Click this pet on the Dock to set a focus timer")
            .disabled(!model.enabledKinds.contains(kind))
            Toggle("", isOn: enabledBinding(for: kind))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    private func avatar(for kind: PetKind) -> some View {
        Circle()
            .fill(avatarColor(for: kind))
            .frame(width: 22, height: 22)
            .overlay {
                Text(String(kind.rawValue.prefix(1)))
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
    }

    private func avatarColor(for kind: PetKind) -> Color {
        switch kind {
        case .girl: return .blue
        case .knight: return .green
        case .warrior: return .orange
        case .hero: return .purple
        case .cat: return .pink
        case .samurai: return .red
        }
    }

    private func enabledBinding(for kind: PetKind) -> Binding<Bool> {
        Binding(
            get: { model.enabledKinds.contains(kind) },
            set: { model.setEnabled($0, for: kind) }
        )
    }

    private func attacksFilesBinding(for kind: PetKind) -> Binding<Bool> {
        Binding(
            get: { model.attacksFiles.contains(kind) },
            set: { model.setAttacksFiles($0, for: kind) }
        )
    }

    private func timerBinding(for kind: PetKind) -> Binding<Bool> {
        Binding(
            get: { model.timerPets.contains(kind) },
            set: { model.setTimerEnabled($0, for: kind) }
        )
    }

    private var timerSoundsBinding: Binding<Bool> {
        Binding(
            get: { model.timerSoundsOn },
            set: { on in
                model.timerSoundsOn = on
                model.onTimerSoundsToggle?(on)
            }
        )
    }

    private var hideAllBinding: Binding<Bool> {
        Binding(
            get: { model.allHidden },
            set: { hidden in
                model.allHidden = hidden
                model.onHideAll?(hidden)
            }
        )
    }
}

#Preview {
    PetRosterView(model: PetRosterModel(
        enabledKinds: [.girl, .knight],
        attacksFiles: [.knight]
    ))
}

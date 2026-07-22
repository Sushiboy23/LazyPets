import SwiftUI

/// Pages of the manage window that other UI (like the pet popover) can ask
/// to open directly.
enum ManagePage {
    case taskList
}

/// The per-pet click/drop features. The manage window assigns a feature to a
/// pet (its icon then appears in the dropdown row); the dropdown icon only
/// arms/disarms it without removing the assignment.
enum PetFeature: String, CaseIterable {
    case attacksFiles
    case timer
    case taskList
    case boombox
    case dial
}

/// View model backing the status-item popover. AppDelegate owns it, injects
/// the side effects (adding/removing pets on the Dock, attacks, persistence),
/// and SwiftUI observes it.
final class PetRosterModel: ObservableObject {

    /// Pets shown on the Dock right now (the dropdown's blue switch).
    @Published var enabledKinds: Set<PetKind>
    /// Pets in the user's rotation — each gets a dropdown row whether or not
    /// it's currently on the Dock. Managed from the manage window's grid;
    /// always a superset of `enabledKinds`.
    @Published var rosterKinds: Set<PetKind> = []
    /// Pets that "attack" files dropped on them (moving the file to the Trash).
    @Published var attacksFiles: Set<PetKind>
    /// Pets that open the focus-timer popover when clicked on the Dock.
    @Published var timerPets: Set<PetKind>
    /// Pets that open their Task List when clicked on the Dock.
    @Published var taskListPets: Set<PetKind>
    /// Pets that show the Boombox (now playing) panel when clicked.
    @Published var boomboxPets: Set<PetKind> = []
    /// Pets that show the Dial (audio devices/volume) panel when clicked.
    @Published var dialPets: Set<PetKind> = []
    /// Assigned features that are currently switched off from the dropdown
    /// row. The icon stays (assignment is the manage window's call); the
    /// feature just doesn't respond until re-armed.
    @Published var disabledFeatures: [PetKind: Set<PetFeature>] = [:]
    /// Starred in the manage window's library.
    @Published var favoriteKinds: Set<PetKind> = []
    /// Display each pet is pinned to (EDID UUID); absent = Default, i.e.
    /// wherever the app launches its pets, exactly as before pinning existed.
    @Published var pinnedDisplays: [PetKind: String] = [:]
    @Published var allHidden: Bool = false
    @Published var timerSoundsOn: Bool = true
    /// One-shot request for the manage window to open on a specific page
    /// (set by e.g. the pet popover's "Manage tasks" button); the window
    /// consumes it and resets it to nil.
    @Published var pendingManagePage: ManagePage?

    var onToggle: ((PetKind, Bool) -> Void)?
    var onAttack: ((PetKind) -> Void)?
    var onAttacksFilesToggle: ((PetKind, Bool) -> Void)?
    var onTimerToggle: ((PetKind, Bool) -> Void)?
    var onTaskListToggle: ((PetKind, Bool) -> Void)?
    var onBoomboxToggle: ((PetKind, Bool) -> Void)?
    var onDialToggle: ((PetKind, Bool) -> Void)?
    var onFeatureActiveChange: ((PetKind, PetFeature, Bool) -> Void)?
    var onTimerSoundsToggle: ((Bool) -> Void)?
    var onFavoriteToggle: ((PetKind, Bool) -> Void)?
    var onRosterChange: ((PetKind, Bool) -> Void)?
    var onPinChange: ((PetKind, String?) -> Void)?
    var onManage: (() -> Void)?
    var onHideAll: ((Bool) -> Void)?
    var onQuit: (() -> Void)?

    init(
        enabledKinds: Set<PetKind> = [],
        attacksFiles: Set<PetKind> = [],
        timerPets: Set<PetKind> = [],
        taskListPets: Set<PetKind> = []
    ) {
        self.enabledKinds = enabledKinds
        self.attacksFiles = attacksFiles
        self.timerPets = timerPets
        self.taskListPets = taskListPets
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

    func setTaskListEnabled(_ on: Bool, for kind: PetKind) {
        if on {
            taskListPets.insert(kind)
        } else {
            taskListPets.remove(kind)
        }
        onTaskListToggle?(kind, on)
    }

    func setBoomboxEnabled(_ on: Bool, for kind: PetKind) {
        if on {
            boomboxPets.insert(kind)
        } else {
            boomboxPets.remove(kind)
        }
        onBoomboxToggle?(kind, on)
    }

    func setDialEnabled(_ on: Bool, for kind: PetKind) {
        if on {
            dialPets.insert(kind)
        } else {
            dialPets.remove(kind)
        }
        onDialToggle?(kind, on)
    }

    // MARK: Feature arming (dropdown icon toggles)

    func isFeatureActive(_ feature: PetFeature, for kind: PetKind) -> Bool {
        !(disabledFeatures[kind]?.contains(feature) ?? false)
    }

    func setFeatureActive(_ active: Bool, _ feature: PetFeature, for kind: PetKind) {
        var muted = disabledFeatures[kind] ?? []
        if active {
            muted.remove(feature)
        } else {
            muted.insert(feature)
        }
        disabledFeatures[kind] = muted
        onFeatureActiveChange?(kind, feature, active)
    }

    /// Assigned AND armed — what the app actually responds to.
    var activeAttacksFiles: Set<PetKind> {
        attacksFiles.filter { isFeatureActive(.attacksFiles, for: $0) }
    }
    var activeTimerPets: Set<PetKind> {
        timerPets.filter { isFeatureActive(.timer, for: $0) }
    }
    var activeTaskListPets: Set<PetKind> {
        taskListPets.filter { isFeatureActive(.taskList, for: $0) }
    }
    var activeBoomboxPets: Set<PetKind> {
        boomboxPets.filter { isFeatureActive(.boombox, for: $0) }
    }
    var activeDialPets: Set<PetKind> {
        dialPets.filter { isFeatureActive(.dial, for: $0) }
    }

    /// Adds/removes the pet from the rotation (the manage grid's toggle).
    /// Joining the roster also puts the pet on the Dock; leaving takes it off.
    func setInRoster(_ on: Bool, for kind: PetKind) {
        if on {
            rosterKinds.insert(kind)
            if !enabledKinds.contains(kind) {
                setEnabled(true, for: kind)
            }
        } else {
            rosterKinds.remove(kind)
            if enabledKinds.contains(kind) {
                setEnabled(false, for: kind)
            }
        }
        onRosterChange?(kind, on)
    }

    func setPinnedDisplay(_ uuid: String?, for kind: PetKind) {
        pinnedDisplays[kind] = uuid
        onPinChange?(kind, uuid)
    }

    func setFavorite(_ on: Bool, for kind: PetKind) {
        if on {
            favoriteKinds.insert(kind)
        } else {
            favoriteKinds.remove(kind)
        }
        onFavoriteToggle?(kind, on)
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

            // Only the user's rotation — the full catalog lives in the
            // manage window, keeping this dropdown fixed-size. The switch
            // shows/hides the pet on the Dock without dropping its row.
            let rosterKinds = PetKind.allCases.filter(model.rosterKinds.contains)
            ForEach(rosterKinds, id: \.rawValue) { kind in
                petRow(for: kind)
            }
            if rosterKinds.isEmpty {
                Text("No pets in your rotation — add some below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            manageRow

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
        .frame(width: 360)
    }

    private func petRow(for kind: PetKind) -> some View {
        HStack(spacing: 8) {
            avatar(for: kind)
            // Priority keeps the name from being squeezed out entirely by
            // the row's six trailing controls.
            Text(kind.rawValue)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 4)
            if !PetAnimations.set(for: kind).attacks.isEmpty {
                Button {
                    model.onAttack?(kind)
                } label: {
                    Image(systemName: "figure.fencing")
                }
                .help("Attack!")
                .disabled(!model.enabledKinds.contains(kind) || model.allHidden)
            }
            // Feature icons appear only while the feature is ticked for this
            // pet in the manage window (which owns the assignment). Clicking
            // an icon here just arms/disarms it — blue = active, plain =
            // paused — without removing it from the row.
            if model.attacksFiles.contains(kind) {
                featureIcon("trash", .attacksFiles, for: kind,
                            help: "Drop a file on this pet to attack it into the Trash")
            }
            if model.timerPets.contains(kind) {
                featureIcon("timer", .timer, for: kind,
                            help: "Click this pet on the Dock to set a focus timer")
            }
            if model.taskListPets.contains(kind) {
                featureIcon("checklist", .taskList, for: kind,
                            help: "Click this pet on the Dock to open its Task List")
            }
            if model.boomboxPets.contains(kind) {
                featureIcon("music.note", .boombox, for: kind,
                            help: "Click this pet on the Dock to open the Boombox")
            }
            if model.dialPets.contains(kind) {
                featureIcon("dial.medium", .dial, for: kind,
                            help: "Click this pet on the Dock to open the Dial audio panel")
            }
            displayMenu(for: kind)
            Toggle("", isOn: enabledBinding(for: kind))
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }

    /// Fifth per-pet control: pin the pet to a display. Blue when pinned,
    /// plain when on Default (today's behavior).
    private func displayMenu(for kind: PetKind) -> some View {
        Menu {
            Picker("Display", selection: pinnedBinding(for: kind)) {
                DisplayPickerOptions(currentPin: model.pinnedDisplays[kind])
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: "display")
                .foregroundStyle(model.pinnedDisplays[kind] != nil ? Color.accentColor : Color.primary)
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Choose which display this pet appears on")
        .disabled(!model.enabledKinds.contains(kind))
    }

    private func pinnedBinding(for kind: PetKind) -> Binding<String?> {
        Binding(
            get: { model.pinnedDisplays[kind] },
            set: { model.setPinnedDisplay($0, for: kind) }
        )
    }

    private var manageRow: some View {
        Button {
            model.onManage?()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                Text("Manage pets and features")
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func avatar(for kind: PetKind) -> some View {
        if let sprite = kind.avatarImage {
            Image(nsImage: sprite)
                .resizable()
                .interpolation(.none) // crisp pixel art
                .scaledToFit()
                .frame(width: 22, height: 22)
        } else {
            Circle()
                .fill(kind.avatarColor)
                .frame(width: 22, height: 22)
                .overlay {
                    Text(String(kind.rawValue.prefix(1)))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
        }
    }

    private func enabledBinding(for kind: PetKind) -> Binding<Bool> {
        Binding(
            get: { model.enabledKinds.contains(kind) },
            set: { model.setEnabled($0, for: kind) }
        )
    }

    /// One assigned feature's arm/disarm toggle in a pet row.
    private func featureIcon(
        _ systemImage: String,
        _ feature: PetFeature,
        for kind: PetKind,
        help: String
    ) -> some View {
        Toggle(isOn: Binding(
            get: { model.isFeatureActive(feature, for: kind) },
            set: { model.setFeatureActive($0, feature, for: kind) }
        )) {
            Image(systemName: systemImage)
        }
        .toggleStyle(.button)
        .help(help)
        .disabled(!model.enabledKinds.contains(kind))
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

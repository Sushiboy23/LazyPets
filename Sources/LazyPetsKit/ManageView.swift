import SwiftUI

/// Content of the "Manage pets and features" window: the full pet library
/// (search, data-driven category chips, card grid) plus one sidebar row per
/// app feature. Shares `PetRosterModel` with the menu bar dropdown, so
/// toggling a pet in either place updates the other immediately.
///
/// Scaling rule: the dropdown only ever shows the active set + fixed rows;
/// anything new — pets or features — gets a sidebar entry here instead.
struct ManageView: View {

    @ObservedObject var model: PetRosterModel
    let taskStore: PetTaskStore
    let audioService: AudioDeviceService
    let levelMonitor: AudioLevelMonitor

    private enum SidebarItem: Hashable {
        case allPets
        case favorites
        case unlockable
        case attacksFiles
        case taskList
        case timers
        case boombox
        case dial
        case displays
        case settings
    }

    @State private var selection: SidebarItem = .allPets
    @State private var searchText = ""
    /// nil = the "All" chip.
    @State private var selectedCategory: String?
    /// The pet in the (single, reusable) preview tab; nil = no preview tab.
    @State private var previewEntry: PetCatalogEntry?
    /// Whether the preview tab is the focused one (vs. the Library tab).
    @State private var isPreviewFocused = false

    private var isPreviewShowing: Bool { isPreviewFocused && previewEntry != nil }

    var body: some View {
        VStack(spacing: 0) {
            if previewEntry != nil {
                tabStrip
                Divider()
            }
            splitView
        }
        .onChange(of: selection) { _ in
            // Picking anything in the sidebar means the user wants library/
            // feature content — surface it, but keep the preview tab around.
            isPreviewFocused = false
        }
        .onAppear(perform: consumePendingPage)
        .onChange(of: model.pendingManagePage) { _ in consumePendingPage() }
    }

    /// Honors a page request set from outside (e.g. the pet popover's
    /// "Manage tasks" button), then clears it so it fires only once.
    private func consumePendingPage() {
        guard let page = model.pendingManagePage else { return }
        switch page {
        case .taskList: selection = .taskList
        }
        isPreviewFocused = false
        model.pendingManagePage = nil
    }

    private var splitView: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Library") {
                    Label("All pets (\(PetCatalog.entries.count))", systemImage: "square.grid.2x2")
                        .tag(SidebarItem.allPets)
                    Label("Favorites", systemImage: "star")
                        .tag(SidebarItem.favorites)
                    Label("Unlockable", systemImage: "lock")
                        .tag(SidebarItem.unlockable)
                }
                Section("Features") {
                    Label("Attacks files", systemImage: "trash")
                        .tag(SidebarItem.attacksFiles)
                    Label("Task list", systemImage: "checklist")
                        .tag(SidebarItem.taskList)
                    Label("Timers", systemImage: "timer")
                        .tag(SidebarItem.timers)
                    Label("Boombox", systemImage: "music.note")
                        .tag(SidebarItem.boombox)
                    Label("Dial", systemImage: "dial.medium")
                        .tag(SidebarItem.dial)
                    Label("Displays", systemImage: "display")
                        .tag(SidebarItem.displays)
                    Label("Settings", systemImage: "gearshape")
                        .tag(SidebarItem.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            // The library stays in the hierarchy (just hidden) while the
            // preview is up, so its search text, filter chips, and scroll
            // position all survive the round trip.
            ZStack {
                detail
                    .opacity(isPreviewShowing ? 0 : 1)
                    .allowsHitTesting(!isPreviewShowing)
                if isPreviewShowing, let entry = previewEntry {
                    PetPreviewView(entry: entry, model: model) {
                        isPreviewFocused = false
                    }
                    .id(entry.id) // fresh stage + idle default per pet
                }
            }
            .frame(minWidth: 440, minHeight: 340)
        }
    }

    // MARK: - Preview tab strip

    private var tabStrip: some View {
        HStack(spacing: 6) {
            tabLabel("Library", isActive: !isPreviewFocused)
                .onTapGesture { isPreviewFocused = false }
            if let entry = previewEntry {
                HStack(spacing: 6) {
                    Text("Preview: \(entry.name)")
                        .font(.callout.weight(isPreviewFocused ? .medium : .regular))
                    Button {
                        previewEntry = nil
                        isPreviewFocused = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close preview")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isPreviewFocused ? Color.accentColor.opacity(0.22) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onTapGesture { isPreviewFocused = true }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func tabLabel(_ title: String, isActive: Bool) -> some View {
        Text(title)
            .font(.callout.weight(isActive ? .medium : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isActive ? Color.accentColor.opacity(0.22) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .allPets:
            library(PetCatalog.entries)
        case .favorites:
            library(PetCatalog.entries.filter { entry in
                entry.kind.map(model.favoriteKinds.contains) ?? false
            }, emptyText: "No favorites yet — star a pet in the library.")
        case .unlockable:
            library(PetCatalog.entries.filter(\.isLocked),
                    emptyText: "No unlockable pets right now.")
        case .attacksFiles:
            featureDetail(
                title: "Attacks files",
                icon: "trash",
                description: "Drop a file on a pet with this enabled — it attacks the file and moves it to the Bin (recoverable, never a permanent delete).",
                isOn: { model.attacksFiles.contains($0) },
                setOn: { model.setAttacksFiles($1, for: $0) },
                supported: { !PetAnimations.set(for: $0).attacks.isEmpty },
                unsupportedHint: "No attack animation"
            )
        case .taskList:
            taskListDetail
        case .timers:
            timersDetail
        case .boombox:
            featureDetail(
                title: "Boombox",
                icon: "music.note",
                description: "Pets with Boombox enabled show what's playing in a supported music app (Spotify or Apple Music) and let you play/pause when clicked on the Dock.",
                isOn: { model.boomboxPets.contains($0) },
                setOn: { model.setBoomboxEnabled($1, for: $0) }
            )
        case .dial:
            dialDetail
        case .displays:
            displaysDetail
        case .settings:
            settingsDetail
        }
    }

    // MARK: - Library grid

    private func library(_ entries: [PetCatalogEntry], emptyText: String? = nil) -> some View {
        let filtered = filter(entries)
        return VStack(alignment: .leading, spacing: 10) {
            TextField("Search pets", text: $searchText)
                .textFieldStyle(.roundedBorder)

            categoryChips

            if filtered.isEmpty {
                Text(searchText.isEmpty ? (emptyText ?? "No pets here.") : "No pets match “\(searchText)”.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    // Lazy: only visible cards are instantiated, so the grid
                    // stays cheap however large the catalog grows.
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                        ForEach(filtered) { entry in
                            card(entry)
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    private func filter(_ entries: [PetCatalogEntry]) -> [PetCatalogEntry] {
        entries.filter { entry in
            (selectedCategory == nil || entry.category == selectedCategory)
                && (searchText.isEmpty || entry.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip("All", isOn: selectedCategory == nil) { selectedCategory = nil }
                ForEach(PetCatalog.categories, id: \.self) { category in
                    chip(category, isOn: selectedCategory == category) {
                        selectedCategory = category
                    }
                }
            }
        }
    }

    private func chip(_ label: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isOn ? Color.accentColor : Color.secondary.opacity(0.18), in: Capsule())
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func card(_ entry: PetCatalogEntry) -> some View {
        VStack(spacing: 8) {
            HStack {
                if let kind = entry.kind, !entry.isLocked {
                    Button {
                        model.setFavorite(!model.favoriteKinds.contains(kind), for: kind)
                    } label: {
                        Image(systemName: model.favoriteKinds.contains(kind) ? "star.fill" : "star")
                            .foregroundStyle(model.favoriteKinds.contains(kind) ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Favorite")
                    Spacer()
                    Toggle("", isOn: rosterBinding(for: kind))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                } else {
                    Spacer()
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .help("Coming soon")
                }
            }
            .frame(height: 20)

            if let kind = entry.kind, !entry.isLocked {
                petAvatar(kind, size: 40)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
            }

            Text(entry.name)
                .font(.callout)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.secondary.opacity(0.2))
        }
        .opacity(entry.isLocked ? 0.55 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 10))
        // Locked pets open the preview too — the lock only affects the CTA.
        .onTapGesture {
            previewEntry = entry
            isPreviewFocused = true
        }
    }

    /// The pet's sprite at full slot size (same treatment as the dropdown
    /// rows), falling back to a colored letter circle if no image loads.
    @ViewBuilder private func petAvatar(_ kind: PetKind, size: CGFloat) -> some View {
        if let sprite = kind.avatarImage {
            Image(nsImage: sprite)
                .resizable()
                .interpolation(.none) // crisp pixel art
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            Circle()
                .fill(kind.avatarColor)
                .frame(width: size, height: size)
                .overlay {
                    Text(String(kind.rawValue.prefix(1)))
                        .font(size >= 40 ? .headline : .caption.bold())
                        .foregroundStyle(.white)
                }
        }
    }

    // MARK: - Feature details

    private func featureDetail(
        title: String,
        icon: String,
        description: String,
        isOn: @escaping (PetKind) -> Bool,
        setOn: @escaping (PetKind, Bool) -> Void,
        supported: @escaping (PetKind) -> Bool = { _ in true },
        unsupportedHint: String = ""
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.title3.weight(.semibold))
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
            featurePetRows(isOn: isOn, setOn: setOn,
                           supported: supported, unsupportedHint: unsupportedHint)
            Spacer()
        }
        .padding(14)
    }

    /// - Parameters:
    ///   - supported: pets the feature can work for at all (e.g. attacking
    ///     files needs an attack animation) — unsupported rows show
    ///     `unsupportedHint` instead of a toggle that would silently do nothing.
    private func featurePetRows(
        isOn: @escaping (PetKind) -> Bool,
        setOn: @escaping (PetKind, Bool) -> Void,
        supported: @escaping (PetKind) -> Bool = { _ in true },
        unsupportedHint: String = ""
    ) -> some View {
        VStack(spacing: 6) {
            ForEach(PetKind.allCases, id: \.rawValue) { kind in
                HStack(spacing: 8) {
                    petAvatar(kind, size: 22)
                    Text(kind.rawValue)
                    Spacer()
                    if supported(kind) {
                        Toggle("", isOn: Binding(get: { isOn(kind) }, set: { setOn(kind, $0) }))
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .labelsHidden()
                            .disabled(!model.enabledKinds.contains(kind))
                    } else {
                        Text(unsupportedHint)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    /// Full task management for the single shared list — the "greater
    /// detail" counterpart to the pet popover's compact panel — plus the
    /// per-pet toggles for which pets open it when clicked.
    private var taskListDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Task list", systemImage: "checklist")
                .font(.title3.weight(.semibold))
            Text("One shared list — clicking any pet with the Task List enabled opens it. Use the eye to hide a task from the popover.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    PetTaskListView(store: taskStore, showsHeader: false, popoverLayout: false, managesHiddenTasks: true)
                        .padding(10)
                        .frame(maxWidth: 460, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.secondary.opacity(0.2))
                        }
                    Text("Pets that open the Task List")
                        .font(.headline)
                    featurePetRows(
                        isOn: { model.taskListPets.contains($0) },
                        setOn: { model.setTaskListEnabled($1, for: $0) }
                    )
                    .frame(maxWidth: 460)
                }
            }
        }
        .padding(14)
    }

    private var timersDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Timers", systemImage: "timer")
                .font(.title3.weight(.semibold))
            Text("Pets with timers enabled open the focus-timer popover when clicked on the Dock.")
                .font(.callout)
                .foregroundStyle(.secondary)
            featurePetRows(
                isOn: { model.timerPets.contains($0) },
                setOn: { model.setTimerEnabled($1, for: $0) }
            )
            Divider()
            Toggle("Timer sounds", isOn: timerSoundsBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
            Spacer()
        }
        .padding(14)
    }

    /// Dial's config page: the same audio control block the popover shows
    /// (shared state — they can't drift), plus the per-pet toggle list.
    private var dialDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Dial", systemImage: "dial.medium")
                .font(.title3.weight(.semibold))
            Text("Control which audio device is active and adjust volume, right from a pet.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    DialAudioBlockView(audio: audioService, levels: levelMonitor)
                        .padding(10)
                        .frame(maxWidth: 460, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.secondary.opacity(0.2))
                        }
                    Text("Pets that show Dial")
                        .font(.headline)
                    featurePetRows(
                        isOn: { model.dialPets.contains($0) },
                        setOn: { model.setDialEnabled($1, for: $0) }
                    )
                    .frame(maxWidth: 460)
                }
            }
        }
        .padding(14)
    }

    private var displaysDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Displays", systemImage: "display")
                .font(.title3.weight(.semibold))
            Text("Pin a pet to a monitor and it always opens there. Default keeps today's behavior. If a pinned monitor is unplugged, the pet falls back to the main display and snaps back when it reconnects.")
                .font(.callout)
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(PetKind.allCases.filter(model.rosterKinds.contains), id: \.rawValue) { kind in
                        HStack(spacing: 8) {
                            petAvatar(kind, size: 22)
                            Text(kind.rawValue)
                            Spacer()
                            Picker("", selection: pinnedBinding(for: kind)) {
                                DisplayPickerOptions(currentPin: model.pinnedDisplays[kind])
                            }
                            .labelsHidden()
                            .frame(width: 220)
                        }
                    }
                }
            }
            Spacer()
        }
        .padding(14)
    }

    private var settingsDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Settings", systemImage: "gearshape")
                .font(.title3.weight(.semibold))
            Toggle("Hide all pets", isOn: Binding(
                get: { model.allHidden },
                set: { hidden in
                    model.allHidden = hidden
                    model.onHideAll?(hidden)
                }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            Toggle("Timer sounds", isOn: timerSoundsBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
            Divider()
            Button("Quit LazyPets") {
                model.onQuit?()
            }
            Spacer()
        }
        .padding(14)
    }

    // MARK: - Bindings

    /// The grid toggle means "in my rotation" (has a dropdown row); the
    /// dropdown's own switch handles on-Dock visibility within the rotation.
    private func rosterBinding(for kind: PetKind) -> Binding<Bool> {
        Binding(
            get: { model.rosterKinds.contains(kind) },
            set: { model.setInRoster($0, for: kind) }
        )
    }

    private func pinnedBinding(for kind: PetKind) -> Binding<String?> {
        Binding(
            get: { model.pinnedDisplays[kind] },
            set: { model.setPinnedDisplay($0, for: kind) }
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
}

#Preview {
    ManageView(
        model: PetRosterModel(
            enabledKinds: [.girl, .knight],
            attacksFiles: [.knight],
            timerPets: [.cat]
        ),
        taskStore: PetTaskStore(),
        audioService: .preview(),
        levelMonitor: .preview(permission: .granted)
    )
}

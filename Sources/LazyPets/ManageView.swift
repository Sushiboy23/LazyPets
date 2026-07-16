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

    private enum SidebarItem: Hashable {
        case allPets
        case favorites
        case unlockable
        case taskList
        case timers
        case settings
    }

    @State private var selection: SidebarItem = .allPets
    @State private var searchText = ""
    /// nil = the "All" chip.
    @State private var selectedCategory: String?

    var body: some View {
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
                    Label("Task list", systemImage: "checklist")
                        .tag(SidebarItem.taskList)
                    Label("Timers", systemImage: "timer")
                        .tag(SidebarItem.timers)
                    Label("Settings", systemImage: "gearshape")
                        .tag(SidebarItem.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 170)
        } detail: {
            detail
                .frame(minWidth: 440, minHeight: 340)
        }
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
        case .taskList:
            featureDetail(
                title: "Task list",
                icon: "checklist",
                description: "Pets with the Task List enabled open it when clicked on the Dock.",
                isOn: { model.taskListPets.contains($0) },
                setOn: { model.setTaskListEnabled($1, for: $0) }
            )
        case .timers:
            timersDetail
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
                    Toggle("", isOn: enabledBinding(for: kind))
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

            Circle()
                .fill(entry.kind?.avatarColor ?? Color.secondary.opacity(0.25))
                .frame(width: 40, height: 40)
                .overlay {
                    if entry.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(entry.name.prefix(1)))
                            .font(.headline)
                            .foregroundStyle(.white)
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
    }

    // MARK: - Feature details

    private func featureDetail(
        title: String,
        icon: String,
        description: String,
        isOn: @escaping (PetKind) -> Bool,
        setOn: @escaping (PetKind, Bool) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.title3.weight(.semibold))
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
            featurePetRows(isOn: isOn, setOn: setOn)
            Spacer()
        }
        .padding(14)
    }

    private func featurePetRows(
        isOn: @escaping (PetKind) -> Bool,
        setOn: @escaping (PetKind, Bool) -> Void
    ) -> some View {
        VStack(spacing: 6) {
            ForEach(PetKind.allCases, id: \.rawValue) { kind in
                HStack(spacing: 8) {
                    Circle()
                        .fill(kind.avatarColor)
                        .frame(width: 22, height: 22)
                        .overlay {
                            Text(String(kind.rawValue.prefix(1)))
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    Text(kind.rawValue)
                    Spacer()
                    Toggle("", isOn: Binding(get: { isOn(kind) }, set: { setOn(kind, $0) }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .disabled(!model.enabledKinds.contains(kind))
                }
            }
        }
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

    private func enabledBinding(for kind: PetKind) -> Binding<Bool> {
        Binding(
            get: { model.enabledKinds.contains(kind) },
            set: { model.setEnabled($0, for: kind) }
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
    ManageView(model: PetRosterModel(
        enabledKinds: [.girl, .knight],
        attacksFiles: [.knight],
        timerPets: [.cat]
    ))
}

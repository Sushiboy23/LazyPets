import SwiftUI

/// One entry in the pet library: a playable `PetKind`, or a locked teaser
/// slot whose art hasn't shipped yet (kind == nil — it can never be enabled,
/// so it never touches the sprite pipeline). Categories drive the manage
/// window's filter chips, so new categories appear there automatically.
struct PetCatalogEntry: Identifiable {
    let kind: PetKind?
    let name: String
    let category: String
    let isLocked: Bool

    var id: String { name }
}

enum PetCatalog {

    static let entries: [PetCatalogEntry] = [
        entry(.girl, category: "Humans"),
        entry(.knight, category: "Fantasy"),
        entry(.warrior, category: "Fantasy"),
        entry(.hero, category: "Fantasy"),
        entry(.cat, category: "Cats"),
        entry(.samurai, category: "Fantasy"),
        // Locked teasers: visible in the library, not orderable. The unlock
        // mechanism itself is deliberately not built yet.
        PetCatalogEntry(kind: nil, name: "Puppy", category: "Dogs", isLocked: true),
        PetCatalogEntry(kind: nil, name: "Dragon", category: "Fantasy", isLocked: true),
        PetCatalogEntry(kind: nil, name: "Wizard", category: "Fantasy", isLocked: true),
    ]

    /// Unique categories in catalog order — the data-driven chip set.
    static var categories: [String] {
        var seen = Set<String>()
        return entries.compactMap { seen.insert($0.category).inserted ? $0.category : nil }
    }

    private static func entry(_ kind: PetKind, category: String) -> PetCatalogEntry {
        PetCatalogEntry(kind: kind, name: kind.rawValue, category: category, isLocked: false)
    }
}

extension PetKind {
    /// Shared avatar tint — the dropdown rows and the manage-window grid
    /// must match.
    var avatarColor: Color {
        switch self {
        case .girl: return .blue
        case .knight: return .green
        case .warrior: return .orange
        case .hero: return .purple
        case .cat: return .pink
        case .samurai: return .red
        }
    }
}

import AppKit
import SpriteKit
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
        entry(.cadet, category: "Humans"),
        entry(.catGirl, category: "Cats"),
        entry(.catGirl2, category: "Cats"),
        entry(.mai, category: "Humans"),
        entry(.fireWizard, category: "Fantasy"), // replaced the "Wizard" teaser
        // Locked teasers: visible in the library, not orderable. The unlock
        // mechanism itself is deliberately not built yet.
        PetCatalogEntry(kind: nil, name: "Puppy", category: "Dogs", isLocked: true),
        PetCatalogEntry(kind: nil, name: "Dragon", category: "Fantasy", isLocked: true),
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
        case .cadet: return .indigo
        case .catGirl: return .cyan
        case .catGirl2: return .teal
        case .mai: return .brown
        case .fireWizard: return .yellow
        }
    }

    /// The pet's actual sprite for avatar circles: first idle frame cropped
    /// to the visible body (reusing the alpha-scan bounds), cached.
    var avatarImage: NSImage? {
        PetAvatarImages.image(for: self)
    }
}

private enum PetAvatarImages {

    private static var cache: [PetKind: NSImage] = [:]

    static func image(for kind: PetKind) -> NSImage? {
        if let cached = cache[kind] {
            return cached
        }
        guard let texture = PetAnimations.set(for: kind).idle.first else { return nil }
        let cgImage = texture.cgImage()
        let unit = PetAnimations.bodyUnitRect(for: kind)
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        // Unit rect is bottom-left origin; CGImage cropping is top-left.
        let cropRect = CGRect(
            x: unit.minX * width,
            y: height - unit.maxY * height,
            width: unit.width * width,
            height: unit.height * height
        )
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        let image = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        cache[kind] = image
        return image
    }
}

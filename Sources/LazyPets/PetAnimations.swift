import ImageIO
import SpriteKit

/// The selectable pets. Raw value doubles as the user-facing menu title.
enum PetKind: String, CaseIterable {
    case girl = "Girl"
    case knight = "Knight"
}

/// Frame arrays + playback metadata for one pet, sliced from its sprite sheets.
struct PetAnimationSet {
    let idle: [SKTexture]
    let walk: [SKTexture]
    /// Played once between idle and the walk loop. Empty = no transition.
    let walkIn: [SKTexture]
    /// One-shot attack variants, one picked at random per trigger. Empty = pet can't attack.
    let attacks: [[SKTexture]]
    /// Which way the source art natively faces; PetNode mirrors relative to this.
    let artFacesRight: Bool

    // Seconds-per-frame for the fixed-timestep stepper (the tuning knobs).
    let idleTimePerFrame: TimeInterval
    let walkTimePerFrame: TimeInterval
    let walkInTimePerFrame: TimeInterval
    let attackTimePerFrame: TimeInterval
}

/// Slices the pixel-art sprite sheets into individual, nearest-filtered
/// `SKTexture` frames and exposes a ready-to-play `PetAnimationSet` per pet.
///
/// Every sheet is a regular grid whose geometry was verified against the
/// PNGs' transparent gutters (empty pixel columns/rows between frames) — not
/// just by dividing the sheet size, which can be ambiguous. If a sheet ever
/// becomes irregular (variable trims, packed atlas), re-export from Aseprite
/// with a JSON data file and drive slicing from the frame rects/tags instead.
enum PetAnimations {

    /// Girl: idle 10×1 @46×55, walk 4×6 @45×58 (gutters at x=44/89/134 rule
    /// out the also-evenly-dividing 5×36 layout), 2-frame idle→walk transition.
    /// Art faces left.
    static let girl = PetAnimationSet(
        idle: slice(sheet: "idle", columns: 10, rows: 1),
        walk: slice(sheet: "walk", columns: 4, rows: 6),
        walkIn: slice(sheet: "transition", columns: 2, rows: 1),
        attacks: [],
        artFacesRight: false,
        idleTimePerFrame: 1.0 / 9.0,
        walkTimePerFrame: 1.0 / 20.0,
        walkInTimePerFrame: 1.0 / 10.0,
        attackTimePerFrame: 0
    )

    /// Knight: single-row 96×84 sheets — idle 7, walk 8, attacks 6/5/6 frames.
    /// All sheets carry a uniform 23px transparent strip below the feet;
    /// cropping it keeps the bottom-anchored feet on the Dock. Art faces right.
    static let knight = PetAnimationSet(
        idle: slice(sheet: "knight_idle", columns: 7, rows: 1, bottomCropPx: 23),
        walk: slice(sheet: "knight_walk", columns: 8, rows: 1, bottomCropPx: 23),
        walkIn: [],
        attacks: [
            slice(sheet: "knight_attack1", columns: 6, rows: 1, bottomCropPx: 23),
            slice(sheet: "knight_attack2", columns: 5, rows: 1, bottomCropPx: 23),
            slice(sheet: "knight_attack3", columns: 6, rows: 1, bottomCropPx: 23),
        ],
        artFacesRight: true,
        idleTimePerFrame: 1.0 / 9.0,
        walkTimePerFrame: 1.0 / 12.0,
        walkInTimePerFrame: 0,
        attackTimePerFrame: 1.0 / 12.0
    )

    static func set(for kind: PetKind) -> PetAnimationSet {
        switch kind {
        case .girl: return girl
        case .knight: return knight
        }
    }

    // MARK: - Slicing

    /// Slices a grid sheet into textures in row-major order (top-left first).
    /// - Parameter bottomCropPx: transparent padding below the art's baseline,
    ///   trimmed from every frame so feet sit on the texture's bottom edge.
    private static func slice(
        sheet name: String,
        columns: Int,
        rows: Int,
        bottomCropPx: Int = 0
    ) -> [SKTexture] {
        guard let cgImage = loadCGImage(named: name) else {
            assertionFailure("Missing sprite sheet resource: \(name).png")
            return []
        }

        let parent = SKTexture(cgImage: cgImage)
        parent.filteringMode = .nearest // crisp pixels — no bilinear blur.

        let frameWidth = 1.0 / CGFloat(columns)
        let frameHeight = 1.0 / CGFloat(rows)
        let crop = CGFloat(bottomCropPx) / CGFloat(cgImage.height)

        var textures: [SKTexture] = []
        textures.reserveCapacity(columns * rows)

        // Sheets are authored top-left origin, row-major. `SKTexture(rect:in:)`
        // uses normalized, bottom-left-origin coordinates, so flip the row.
        for row in 0..<rows {
            for column in 0..<columns {
                let rect = CGRect(
                    x: CGFloat(column) * frameWidth,
                    y: 1.0 - CGFloat(row + 1) * frameHeight + crop,
                    width: frameWidth,
                    height: frameHeight - crop
                )
                let frame = SKTexture(rect: rect, in: parent)
                frame.filteringMode = .nearest
                textures.append(frame)
            }
        }
        return textures
    }

    /// Loads a PNG from the module bundle as a `CGImage` so slicing uses exact
    /// pixel dimensions (bypassing any NSImage point/DPI scaling).
    private static func loadCGImage(named name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }
}

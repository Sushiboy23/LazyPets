import ImageIO
import SpriteKit

/// Slices the pixel-art sprite sheets into individual, nearest-filtered
/// `SKTexture` frames and exposes ready-to-play frame arrays for each
/// animation state.
///
/// Every sheet is a regular grid, so frame rects are derived from the sheet's
/// pixel size and its grid dimensions — no external JSON is needed. If a sheet
/// ever becomes irregular (variable trims, packed atlas), re-export from
/// Aseprite with a JSON data file and drive slicing from the frame rects/tags
/// instead.
///
/// Playback is a fixed-timestep frame stepper (`SKAction.animate(withTextures:)`),
/// deliberately not spring/easing, so pixels advance on whole frames. The
/// per-frame durations below are the tuning knobs — adjust by eye in the app.
enum PetAnimations {

    // Seconds-per-frame for the fixed-timestep stepper.
    static let idleTimePerFrame: TimeInterval = 1.0 / 9.0        // ~9 fps
    static let walkTimePerFrame: TimeInterval = 1.0 / 12.0       // ~12 fps
    static let transitionTimePerFrame: TimeInterval = 1.0 / 10.0 // ~10 fps

    /// Idle: 10-frame horizontal strip (460×55, 46×55 per frame). Loops forever.
    static let idle: [SKTexture] = slice(sheet: "idle", columns: 10, rows: 1)

    /// Walk: 5×6 grid (180×348, 36×58 per frame). Only the first 26 cells are
    /// used — the last 4 are empty — so we drop them. Side-on cycle facing right.
    static let walk: [SKTexture] = Array(
        slice(sheet: "walk", columns: 5, rows: 6, usableFrames: 26)
    )

    /// Idle→walk transition: 2-frame strip (90×58, 45×58 per frame). Plays once.
    static let transition: [SKTexture] = slice(sheet: "transition", columns: 2, rows: 1)

    // MARK: - Slicing

    /// Slices a grid sheet into textures in row-major order (top-left first).
    /// - Parameter usableFrames: cap for sheets whose trailing cells are empty.
    private static func slice(
        sheet name: String,
        columns: Int,
        rows: Int,
        usableFrames: Int? = nil
    ) -> [SKTexture] {
        guard let cgImage = loadCGImage(named: name) else {
            assertionFailure("Missing sprite sheet resource: \(name).png")
            return []
        }

        let parent = SKTexture(cgImage: cgImage)
        parent.filteringMode = .nearest // crisp pixels — no bilinear blur.

        let frameWidth = 1.0 / CGFloat(columns)
        let frameHeight = 1.0 / CGFloat(rows)
        let limit = usableFrames ?? (columns * rows)

        var textures: [SKTexture] = []
        textures.reserveCapacity(limit)

        // Sheets are authored top-left origin, row-major. `SKTexture(rect:in:)`
        // uses normalized, bottom-left-origin coordinates, so flip the row.
        outer: for row in 0..<rows {
            for column in 0..<columns {
                guard textures.count < limit else { break outer }
                let rect = CGRect(
                    x: CGFloat(column) * frameWidth,
                    y: 1.0 - CGFloat(row + 1) * frameHeight,
                    width: frameWidth,
                    height: frameHeight
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

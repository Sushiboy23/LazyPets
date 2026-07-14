import ImageIO
import SpriteKit

/// The selectable pets. Raw value doubles as the user-facing menu title.
enum PetKind: String, CaseIterable {
    case girl = "Girl"
    case knight = "Knight"
    case warrior = "Blonde Warrior"
    case hero = "Male Hero"
    case cat = "Cat"
    case samurai = "Samurai"
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
    /// Per-pet render scale, chosen so pets look the same size on screen even
    /// though their characters fill different fractions of their frames (girl's
    /// body is 55px tall in-frame, knight's only 35px, warrior's ~120px).
    /// Prefer multiples of 0.5 so each art pixel maps to a whole number of
    /// Retina device pixels; fine-resolution art can bend this (see warrior).
    let pixelScale: CGFloat
    /// Ground speed in points/second. Tune together with `walkTimePerFrame`
    /// so stride length matches movement — too fast and the feet slide, too
    /// slow and the pet runs in place.
    let walkSpeed: CGFloat

    // Seconds-per-frame for the fixed-timestep stepper (the tuning knobs).
    let idleTimePerFrame: TimeInterval
    let walkTimePerFrame: TimeInterval
    let walkInTimePerFrame: TimeInterval
    let attackTimePerFrame: TimeInterval

    // Optional extra gaits — empty/zero means the pet doesn't have them and
    // the state machine will never pick them. (`var` + default so the
    // memberwise init lets older pets omit these entirely.)

    /// Faster gait, picked at random instead of walking.
    var run: [SKTexture] = []
    var runTimePerFrame: TimeInterval = 0
    var runSpeed: CGFloat = 0
    /// In-place hop (ascent + descent frames combined), triggered from idle.
    var jump: [SKTexture] = []
    var jumpTimePerFrame: TimeInterval = 0
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
        pixelScale: 1.5,
        walkSpeed: 110,
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
        pixelScale: 2.5,
        walkSpeed: 110,
        idleTimePerFrame: 1.0 / 9.0,
        walkTimePerFrame: 1.0 / 12.0,
        walkInTimePerFrame: 0,
        attackTimePerFrame: 1.0 / 12.0
    )

    /// Blonde warrior: 54 individual 256×256 frame PNGs (not sheets) — idle 8,
    /// walk 10, and 5 attack combos of 6/6/7/11/6 frames. Her body is ~120px
    /// tall in-frame with feet at rows 241-249, so crop the uniform 6px below
    /// the lowest baseline. Art faces right (eye/toes/shield-front — verify
    /// zoomed-in before trusting a glance; the hair reads misleadingly).
    ///
    /// pixelScale 0.7 is deliberately not a Retina half-step: at this art
    /// resolution (~120px body vs the others' ~35-55px) a fractional device
    /// mapping is far less visible than the size mismatch it fixes — 0.5 would
    /// leave her a head shorter than the girl.
    static let warrior = PetAnimationSet(
        idle: frames("warrior_idle", count: 8, bottomCropPx: 6),
        walk: frames("warrior_walk", count: 10, bottomCropPx: 6),
        walkIn: [],
        attacks: [
            frames("warrior_attack1", count: 6, bottomCropPx: 6),
            frames("warrior_attack2", count: 6, bottomCropPx: 6),
            frames("warrior_attack3", count: 7, bottomCropPx: 6),
            frames("warrior_attack4", count: 11, bottomCropPx: 6),
            frames("warrior_attack5", count: 6, bottomCropPx: 6),
        ],
        artFacesRight: true,
        pixelScale: 0.7,
        walkSpeed: 65,
        idleTimePerFrame: 1.0 / 9.0,
        walkTimePerFrame: 1.0 / 12.0,
        walkInTimePerFrame: 0,
        attackTimePerFrame: 1.0 / 12.0
    )

    /// Male hero (Ozzbit Games, free version — personal use, credit required):
    /// single-row 128×128 sheets with a uniform 48px strip below the feet —
    /// idle/walk/run 10 frames, jump 6 + fall 4 (combined into one hop arc),
    /// combo_1 3, combo_1_end 4. Attack move 1 is the quick opening slash;
    /// move 2 chains the full combo. Art faces right.
    static let hero: PetAnimationSet = {
        let combo1 = slice(sheet: "hero_combo1", columns: 3, rows: 1, bottomCropPx: 48)
        let combo1End = slice(sheet: "hero_combo1_end", columns: 4, rows: 1, bottomCropPx: 48)
        return PetAnimationSet(
            idle: slice(sheet: "hero_idle", columns: 10, rows: 1, bottomCropPx: 48),
            walk: slice(sheet: "hero_walk", columns: 10, rows: 1, bottomCropPx: 48),
            walkIn: [],
            attacks: [
                combo1,
                combo1 + combo1End,
            ],
            artFacesRight: true,
            pixelScale: 2.5,
            walkSpeed: 90,
            idleTimePerFrame: 1.0 / 9.0,
            walkTimePerFrame: 1.0 / 12.0,
            walkInTimePerFrame: 0,
            attackTimePerFrame: 1.0 / 10.0,
            run: slice(sheet: "hero_run", columns: 10, rows: 1, bottomCropPx: 48),
            runTimePerFrame: 1.0 / 15.0,
            runSpeed: 220,
            jump: slice(sheet: "hero_jump", columns: 6, rows: 1, bottomCropPx: 48)
                + slice(sheet: "hero_fall", columns: 4, rows: 1, bottomCropPx: 48),
            jumpTimePerFrame: 1.0 / 12.0
        )
    }()

    /// Cat: single-row 80×64 sheets — idle 8, walk 12, run 8, jump 3, attack 8
    /// frames. Bottom padding varies slightly per sheet (grounded anims 16px,
    /// pounce/airborne dip lower), so each sheet crops its own measured pad.
    /// Body is only ~28px tall — 2.0× keeps him properly cat-sized next to
    /// the human pets. Art faces left. (The pack's 3-frame RUNNING JUMP sheet
    /// is unused — the state machine only has an in-place hop.)
    static let cat = PetAnimationSet(
        idle: slice(sheet: "cat_idle", columns: 8, rows: 1, bottomCropPx: 16),
        walk: slice(sheet: "cat_walk", columns: 12, rows: 1, bottomCropPx: 16),
        walkIn: [],
        attacks: [
            slice(sheet: "cat_attack", columns: 8, rows: 1, bottomCropPx: 14),
        ],
        artFacesRight: false,
        pixelScale: 2.0,
        walkSpeed: 55,
        idleTimePerFrame: 1.0 / 8.0,
        walkTimePerFrame: 1.0 / 12.0,
        walkInTimePerFrame: 0,
        attackTimePerFrame: 1.0 / 12.0,
        run: slice(sheet: "cat_run", columns: 8, rows: 1, bottomCropPx: 16),
        runTimePerFrame: 1.0 / 15.0,
        runSpeed: 180,
        jump: slice(sheet: "cat_jump", columns: 3, rows: 1, bottomCropPx: 17),
        jumpTimePerFrame: 1.0 / 8.0
    )

    /// Samurai: single-row 96×96 sheets — idle 10, run 16, attack 7 frames,
    /// ~15px bottom padding. The free pack has NO walk sheet (slowed-down run
    /// frames looked floaty), so `walk` is empty and the state machine always
    /// runs him instead. Art faces right.
    static let samurai = PetAnimationSet(
        idle: slice(sheet: "samurai_idle", columns: 10, rows: 1, bottomCropPx: 15),
        walk: [],
        walkIn: [],
        attacks: [
            slice(sheet: "samurai_attack", columns: 7, rows: 1, bottomCropPx: 14),
        ],
        artFacesRight: true,
        pixelScale: 2.5,
        walkSpeed: 0,
        idleTimePerFrame: 1.0 / 9.0,
        walkTimePerFrame: 0,
        walkInTimePerFrame: 0,
        attackTimePerFrame: 1.0 / 12.0,
        run: slice(sheet: "samurai_run", columns: 16, rows: 1, bottomCropPx: 15),
        runTimePerFrame: 1.0 / 18.0,
        runSpeed: 240
    )

    static func set(for kind: PetKind) -> PetAnimationSet {
        switch kind {
        case .girl: return girl
        case .knight: return knight
        case .warrior: return warrior
        case .hero: return hero
        case .cat: return cat
        case .samurai: return samurai
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

    /// Loads an animation exported as individual frame PNGs named
    /// `<base>_01.png` … `<base>_NN.png` (one texture per file, no slicing).
    /// - Parameter bottomCropPx: transparent padding below the art's baseline,
    ///   trimmed so feet sit on the texture's bottom edge.
    private static func frames(
        _ base: String,
        count: Int,
        bottomCropPx: Int = 0
    ) -> [SKTexture] {
        (1...count).compactMap { index in
            let name = String(format: "%@_%02d", base, index)
            guard let cgImage = loadCGImage(named: name) else {
                assertionFailure("Missing sprite frame resource: \(name).png")
                return nil
            }
            let full = SKTexture(cgImage: cgImage)
            full.filteringMode = .nearest
            guard bottomCropPx > 0 else { return full }

            let crop = CGFloat(bottomCropPx) / CGFloat(cgImage.height)
            let trimmed = SKTexture(
                rect: CGRect(x: 0, y: crop, width: 1, height: 1 - crop),
                in: full
            )
            trimmed.filteringMode = .nearest
            return trimmed
        }
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

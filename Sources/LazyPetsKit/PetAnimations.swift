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
    case cadet = "Cadet"
    case catGirl = "Cat Girl"
    case catGirl2 = "Cat Girl 2"
    case mai = "Mai"
    case fireWizard = "Fire Wizard"
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
    /// Played once between idle and the run loop. Empty = no transition.
    var runIn: [SKTexture] = []
    var runInTimePerFrame: TimeInterval = 0
    /// In-place hop (ascent + descent frames combined), triggered from idle.
    var jump: [SKTexture] = []
    var jumpTimePerFrame: TimeInterval = 0
    /// Rare alternate idle clips: after a few passes of the main `idle` loop,
    /// one variant plays once, then the main loop resumes — so the main idle
    /// still fills most of the resting time. Empty = only one idle.
    var idleVariants: [[SKTexture]] = []
    var idleVariantTimePerFrame: TimeInterval = 0
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

    /// Cadet (anime style, not pixel art): idle/walk are 5×5 alpha sheets
    /// (25 cells; the 25th duplicates the 1st, so it's dropped for a clean
    /// 24-frame loop), pre-downscaled 1280→1060 so her 175px body matches the
    /// attack sheet's 145px scale. Per-sheet bottom crops put the feet
    /// baseline (measured from the alpha) on the texture edge. Attack is the
    /// 8-frame kneel→aim→fire strip extracted from the original turnaround
    /// sheet. 0.6× matches the other pets' on-screen height. Art faces right.
    static let cadet = PetAnimationSet(
        idle: Array(slice(sheet: "cadet_idle", columns: 5, rows: 5, bottomCropPx: 31).dropLast()),
        walk: Array(slice(sheet: "cadet_walk", columns: 5, rows: 5, bottomCropPx: 30).dropLast()),
        walkIn: [],
        attacks: [
            slice(sheet: "cadet_attack", columns: 8, rows: 1),
        ],
        artFacesRight: true,
        pixelScale: 0.6,
        walkSpeed: 65,
        idleTimePerFrame: 1.0 / 8.0,
        walkTimePerFrame: 1.0 / 15.0,
        walkInTimePerFrame: 0,
        attackTimePerFrame: 1.0 / 10.0
    )

    /// Cat girl: sheets baked at half resolution from a screenshot capture of
    /// the source sprite sheet (checkerboard background flood-filled out, rows
    /// re-cut per frame) — originals live outside the repo. Single-row sheets:
    /// idle 5 @103×106, walk 8 @103×104, run 8 @103×101, attack 6 @300×106
    /// (attack cells are extra-wide with the feet at the cell center so the
    /// sword-slash trails fit without shifting the body between states).
    /// Feet baselines already sit on the texture edge — no bottom crops.
    /// Body is ~106px tall; 0.8× (fine-res art, warrior-style non-half-step)
    /// matches the other pets' on-screen height. Art faces right.
    static let catGirl = PetAnimationSet(
        idle: slice(sheet: "catgirl_idle", columns: 5, rows: 1),
        walk: slice(sheet: "catgirl_walk", columns: 8, rows: 1),
        walkIn: [],
        attacks: [
            slice(sheet: "catgirl_attack", columns: 6, rows: 1),
        ],
        artFacesRight: true,
        pixelScale: 0.8,
        walkSpeed: 45,
        idleTimePerFrame: 1.0 / 8.0,
        walkTimePerFrame: 1.0 / 12.0,
        walkInTimePerFrame: 0,
        attackTimePerFrame: 1.0 / 12.0,
        run: slice(sheet: "catgirl_run", columns: 8, rows: 1),
        runTimePerFrame: 1.0 / 15.0,
        runSpeed: 200
    )

    /// Cat girl 2 (anime style, same generator as the Cadet's v1 sheets):
    /// idle/walk are 5×5 alpha sheets of 256px cells; the 25th cell duplicates
    /// the 1st, so both drop it for clean 24-frame loops. The idle sheet
    /// shipped with a flat gray backdrop blob baked behind each cell —
    /// flood-filled out (un-premultiplied gray test so the soft edges didn't
    /// block the fill; a whiteness threshold would have punched holes in her
    /// white coat). Feet baseline y=223 in every cell → uniform 32px bottom
    /// crop. No attack/run sheets in the pack. Body ~187px tall; 0.45×
    /// matches the other pets' on-screen height. Art faces right.
    static let catGirl2 = PetAnimationSet(
        idle: Array(slice(sheet: "catgirl2_idle", columns: 5, rows: 5, bottomCropPx: 32).dropLast()),
        walk: Array(slice(sheet: "catgirl2_walk", columns: 5, rows: 5, bottomCropPx: 32).dropLast()),
        walkIn: [],
        attacks: [],
        artFacesRight: true,
        pixelScale: 0.45,
        walkSpeed: 65,
        idleTimePerFrame: 1.0 / 8.0,
        walkTimePerFrame: 1.0 / 15.0,
        walkInTimePerFrame: 0,
        attackTimePerFrame: 0
    )

    /// Mai (anime schoolgirl with a pistol, same generator as Cat Girl 2):
    /// six 5×5 alpha sheets of 256px cells — and unlike the other v1 bakes,
    /// the 25th cell is a real frame on every sheet (verified: it differs
    /// from the 1st far more than neighbors do), so nothing is dropped.
    /// idle1 is the main idle; idle2 (pistol check) and idle3 (arms crossed,
    /// gun set down) are rare variants via `idleVariants`. Feet baselines
    /// vary per sheet, hence the per-sheet bottom crops. The attack's muzzle
    /// flash clips at its own cell edge in the source art. Body ~200px tall;
    /// 0.45× matches the other pets' on-screen height. Art faces right.
    static let mai = PetAnimationSet(
        idle: slice(sheet: "mai_idle1", columns: 5, rows: 5, bottomCropPx: 25),
        walk: slice(sheet: "mai_walk", columns: 5, rows: 5, bottomCropPx: 35),
        walkIn: [],
        attacks: [
            slice(sheet: "mai_attack", columns: 5, rows: 5, bottomCropPx: 33),
        ],
        artFacesRight: true,
        pixelScale: 0.45,
        walkSpeed: 65,
        idleTimePerFrame: 1.0 / 8.0,
        walkTimePerFrame: 1.0 / 15.0,
        walkInTimePerFrame: 0,
        attackTimePerFrame: 1.0 / 12.0,
        run: slice(sheet: "mai_run", columns: 5, rows: 5, bottomCropPx: 26),
        runTimePerFrame: 1.0 / 12.0,
        runSpeed: 140,
        idleVariants: [
            slice(sheet: "mai_idle2", columns: 5, rows: 5, bottomCropPx: 33),
            slice(sheet: "mai_idle3", columns: 5, rows: 5, bottomCropPx: 33),
        ],
        idleVariantTimePerFrame: 1.0 / 8.0
    )

    /// Fire wizard (anime style, same generator as Cat Girl 2/Mai): 5×5
    /// alpha sheets of 256px cells. Idle/walk's 25th cell duplicates the 1st
    /// (dropped); the attacks' 25th are real frames (kept); the run sheet
    /// splits into an idle→run intro + stride loop (see below).
    /// Fire effects clip at their own cell edge in the source art, like
    /// Mai's muzzle flash. Feet baselines vary per sheet → per-sheet crops;
    /// attack 3's crop (33) is set from its *standing* frames — mid-lunge his
    /// back foot slides ~10px lower and clips rather than having him float
    /// at the attack's start/end. Attack variants: hurled fireball / fire
    /// vortex that engulfs him / horizontal flame stream (one picked at
    /// random per drop). Body ~190px tall; 0.45× matches the other pets.
    /// Art faces right.
    static let fireWizard = PetAnimationSet(
        idle: Array(slice(sheet: "wizard_idle", columns: 5, rows: 5, bottomCropPx: 31).dropLast()),
        walk: Array(slice(sheet: "wizard_walk", columns: 5, rows: 5, bottomCropPx: 36).dropLast()),
        walkIn: [],
        attacks: [
            slice(sheet: "wizard_attack", columns: 5, rows: 5, bottomCropPx: 32),
            slice(sheet: "wizard_attack2", columns: 5, rows: 5, bottomCropPx: 33),
            slice(sheet: "wizard_attack3", columns: 5, rows: 5, bottomCropPx: 33),
        ],
        artFacesRight: true,
        pixelScale: 0.45,
        walkSpeed: 65,
        idleTimePerFrame: 1.0 / 8.0,
        walkTimePerFrame: 1.0 / 15.0,
        walkInTimePerFrame: 0,
        attackTimePerFrame: 1.0 / 12.0,
        // Run sheet (v2): cells 1-5 are near-static idle-stance duplicates
        // (dropped — a standing pose would slide across the Dock), 6-8 the
        // idle→run lean-in (played once), 9-25 the stride loop.
        run: Array(slice(sheet: "wizard_run", columns: 5, rows: 5, bottomCropPx: 31)[8...]),
        runTimePerFrame: 1.0 / 12.0,
        runSpeed: 140,
        runIn: Array(slice(sheet: "wizard_run", columns: 5, rows: 5, bottomCropPx: 31)[5..<8]),
        runInTimePerFrame: 1.0 / 12.0
    )

    static func set(for kind: PetKind) -> PetAnimationSet {
        switch kind {
        case .girl: return girl
        case .knight: return knight
        case .warrior: return warrior
        case .hero: return hero
        case .cat: return cat
        case .samurai: return samurai
        case .cadet: return cadet
        case .catGirl: return catGirl
        case .catGirl2: return catGirl2
        case .mai: return mai
        case .fireWizard: return fireWizard
        }
    }

    // MARK: - Body bounds

    /// Bounding box of the character's opaque pixels within its idle frame, in
    /// unit texture coordinates (0–1, bottom-left origin). Frames carry lots of
    /// transparent padding around the body (the warrior's is ~120px in a 256px
    /// frame), so anything that should hug the visible character — like the
    /// file-drop glow — uses this instead of the full frame. Measured once per
    /// kind from the first idle frame; body proportions are close enough across
    /// states that one measurement serves them all.
    static func bodyUnitRect(for kind: PetKind) -> CGRect {
        if let cached = bodyRectCache[kind] { return cached }
        let fullFrame = CGRect(x: 0, y: 0, width: 1, height: 1)
        var rect = fullFrame
        if let texture = set(for: kind).idle.first {
            rect = opaqueUnitRect(of: texture.cgImage()) ?? fullFrame
        }
        bodyRectCache[kind] = rect
        return rect
    }

    private static var bodyRectCache: [PetKind: CGRect] = [:]

    /// Scans the image's alpha channel for the tight bounding box of visible
    /// pixels, returned in unit coordinates with a bottom-left origin (to match
    /// texture space). Nil if the image is fully transparent.
    private static func opaqueUnitRect(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }

        // RGBA — the alpha byte is the 4th component of each pixel.
        let bytesPerRow = context.bytesPerRow
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        var minX = width, maxX = -1, minRow = height, maxRow = -1
        for row in 0..<height {
            for column in 0..<width where pixels[row * bytesPerRow + column * 4 + 3] > 25 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minRow = min(minRow, row)
                maxRow = max(maxRow, row)
            }
        }
        guard maxX >= 0 else { return nil }

        // Buffer row 0 is the image's top row; flip to bottom-left origin.
        return CGRect(
            x: CGFloat(minX) / CGFloat(width),
            y: CGFloat(height - 1 - maxRow) / CGFloat(height),
            width: CGFloat(maxX - minX + 1) / CGFloat(width),
            height: CGFloat(maxRow - minRow + 1) / CGFloat(height)
        )
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

    /// Where the sprite PNGs live: the SwiftPM resource bundle when built via
    /// `swift build` / build_app.sh, the app bundle itself when built by the
    /// Xcode app target (which has no Bundle.module).
    #if SWIFT_PACKAGE
    private static let spriteBundle = Bundle.module
    #else
    private static let spriteBundle = Bundle.main
    #endif

    /// Loads a PNG from the sprite bundle as a `CGImage` so slicing uses exact
    /// pixel dimensions (bypassing any NSImage point/DPI scaling).
    private static func loadCGImage(named name: String) -> CGImage? {
        guard let url = spriteBundle.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }
}

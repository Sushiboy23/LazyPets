import AppKit
import SpriteKit
import SwiftUI

/// The animations a pet can demo on the preview stage. Pills are only shown
/// for actions the pet's `PetAnimationSet` actually contains.
enum PetPreviewAction: String, CaseIterable, Identifiable {
    case idle = "Idle"
    case walk = "Walk"
    case run = "Run"
    case jump = "Jump"
    case attack = "Attack"

    var id: String { rawValue }

    static func available(for kind: PetKind) -> [PetPreviewAction] {
        let set = PetAnimations.set(for: kind)
        var actions: [PetPreviewAction] = [.idle]
        if !set.walk.isEmpty { actions.append(.walk) }
        if !set.run.isEmpty { actions.append(.run) }
        if !set.jump.isEmpty { actions.append(.jump) }
        if !set.attacks.isEmpty { actions.append(.attack) }
        return actions
    }
}

/// One playable animation for the stage: the same frames and per-frame timing
/// the desktop pets use, converted to `NSImage`s and sized so the visible
/// body stands ~110pt tall regardless of each pet's art padding.
///
/// The stage animates these with SwiftUI's clock (`TimelineView`) instead of
/// presenting an `SKScene`: SpriteKit's view render loop refuses to advance
/// inside the manage window (both `SpriteView` and a raw `SKView` rendered a
/// single frozen frame), while SwiftUI's own updates demonstrably work there.
private struct PreviewClip {
    let frames: [NSImage]
    let timePerFrame: TimeInterval
    /// Points per art pixel — applied per frame, since sheets can have
    /// slightly different frame dimensions within one clip (e.g. attack
    /// frames interleaved with idle rest frames).
    let scale: CGFloat
    let started = Date()

    static func make(kind: PetKind, action: PetPreviewAction) -> PreviewClip? {
        let set = PetAnimations.set(for: kind)
        let frames: [NSImage]
        let timePerFrame: TimeInterval
        switch action {
        case .idle:
            (frames, timePerFrame) = (convert(set.idle), set.idleTimePerFrame)
        case .walk:
            (frames, timePerFrame) = (convert(set.walk), set.walkTimePerFrame)
        case .run:
            (frames, timePerFrame) = (convert(set.run), set.runTimePerFrame)
        case .jump:
            (frames, timePerFrame) = (convert(set.jump), set.jumpTimePerFrame)
        case .attack:
            timePerFrame = set.attackTimePerFrame
            // Chain every attack pattern the pet has, resting in the idle
            // pose for a beat between swings so each pattern reads as its
            // own attack instead of one continuous blur.
            let restTicks = max(1, Int((0.9 / max(timePerFrame, 0.01)).rounded()))
            let rest = set.idle.first.map { Array(repeating: convert([$0])[0], count: restTicks) } ?? []
            frames = set.attacks.flatMap { convert($0) + rest }
        }
        guard !frames.isEmpty, timePerFrame > 0 else { return nil }

        // Shared points-per-pixel scale derived from the idle body height, so
        // the pet stays the same size when switching between actions even
        // though their sheets have different frame dimensions.
        let idleFrameHeight = CGFloat(set.idle.first.map { $0.cgImage().height } ?? 1)
        let bodyHeight = PetAnimations.bodyUnitRect(for: kind).height * idleFrameHeight
        return PreviewClip(
            frames: frames,
            timePerFrame: timePerFrame,
            scale: 110 / max(bodyHeight, 1)
        )
    }

    private static func convert(_ textures: [SKTexture]) -> [NSImage] {
        textures.map { texture in
            let cgImage = texture.cgImage()
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
    }
}

/// Body of the manage window's "Preview: <Pet>" tab: header with editable
/// favorite star, the animated stage, one pill per available animation, and
/// a state-aware primary CTA. Locked entries (no `kind`) show a lock
/// placeholder stage since they have no art yet.
struct PetPreviewView: View {

    let entry: PetCatalogEntry
    @ObservedObject var model: PetRosterModel
    let onBackToLibrary: () -> Void

    @State private var action: PetPreviewAction = .idle
    @State private var clip: PreviewClip?

    init(entry: PetCatalogEntry, model: PetRosterModel, onBackToLibrary: @escaping () -> Void) {
        self.entry = entry
        self.model = model
        self.onBackToLibrary = onBackToLibrary
        _clip = State(initialValue: entry.kind.flatMap { PreviewClip.make(kind: $0, action: .idle) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            stage
            if entry.kind != nil {
                Text("Now playing: \(action.rawValue) (loops)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                pills
            }
            Spacer(minLength: 0)
            HStack {
                Button("← Back to Library", action: onBackToLibrary)
                    .buttonStyle(.link)
                Spacer()
                cta
            }
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(entry.name)
                .font(.title2.weight(.semibold))
            Text(entry.category)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.18), in: Capsule())
            Spacer()
            if let kind = entry.kind, !entry.isLocked {
                Button {
                    model.setFavorite(!model.favoriteKinds.contains(kind), for: kind)
                } label: {
                    Image(systemName: model.favoriteKinds.contains(kind) ? "star.fill" : "star")
                        .font(.title3)
                        .foregroundStyle(model.favoriteKinds.contains(kind) ? Color.yellow : Color.secondary)
                }
                .buttonStyle(.plain)
                .help("Favorite")
            }
        }
    }

    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
            if let clip {
                TimelineView(.periodic(from: clip.started, by: clip.timePerFrame)) { context in
                    let elapsed = max(0, context.date.timeIntervalSince(clip.started))
                    let step = Int(elapsed / clip.timePerFrame)
                    let image = clip.frames[step % clip.frames.count]
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.none) // crisp pixel art
                        .frame(width: image.size.width * clip.scale, height: image.size.height * clip.scale)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 20)
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var pills: some View {
        HStack(spacing: 6) {
            ForEach(PetPreviewAction.available(for: entry.kind!)) { pill in
                Button {
                    action = pill
                    clip = entry.kind.flatMap { PreviewClip.make(kind: $0, action: pill) }
                } label: {
                    Text(pill.rawValue)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            action == pill ? Color.accentColor : Color.secondary.opacity(0.18),
                            in: Capsule()
                        )
                        .foregroundStyle(action == pill ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder private var cta: some View {
        if let kind = entry.kind, !entry.isLocked {
            if model.rosterKinds.contains(kind) {
                Button {} label: {
                    Label("Currently selected", systemImage: "checkmark")
                }
                .disabled(true)
            } else {
                Button("Select this pet") {
                    model.setInRoster(true, for: kind)
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            // TODO: Show the real unlock requirement (achievement, purchase, …)
            // once an unlock mechanism exists in the model — nothing is
            // defined yet, so this CTA is a disabled stub.
            Button {} label: {
                Label("Unlock this pet", systemImage: "lock.fill")
            }
            .disabled(true)
        }
    }
}

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

    /// Mirrors the dock state machine: idle/walk/run are ambient loops,
    /// jump/attack are one-shot triggers that return to idle.
    var loops: Bool {
        switch self {
        case .idle, .walk, .run: return true
        case .jump, .attack: return false
        }
    }

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

/// Minimal scene for the preview stage: one bottom-anchored sprite standing
/// on a baseline, playing the same textures/frame timings as the dock pets
/// but scaled up so the body reads clearly at window size.
final class PetPreviewScene: SKScene {

    private let animations: PetAnimationSet
    private let sprite = SKSpriteNode()
    /// Called when a one-shot action finishes and the stage falls back to idle.
    var onReturnToIdle: (() -> Void)?

    init(kind: PetKind) {
        animations = PetAnimations.set(for: kind)
        super.init(size: CGSize(width: 400, height: 220))
        scaleMode = .resizeFill
        backgroundColor = .clear

        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        if let first = animations.idle.first {
            sprite.texture = first
            sprite.size = first.size()
        }
        // Scale so the visible body (not the padded frame) is ~110pt tall,
        // regardless of how much transparent padding each pet's art carries.
        let frameHeight = animations.idle.first?.size().height ?? 1
        let bodyHeight = PetAnimations.bodyUnitRect(for: kind).height * frameHeight
        sprite.setScale(110 / max(bodyHeight, 1))
        addChild(sprite)
        play(.idle)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) { layoutSprite() }
    override func didChangeSize(_ oldSize: CGSize) { layoutSprite() }

    private func layoutSprite() {
        sprite.position = CGPoint(x: size.width / 2, y: 20)
    }

    func play(_ action: PetPreviewAction) {
        sprite.removeAllActions()
        let frames: [SKTexture]
        let timePerFrame: TimeInterval
        switch action {
        case .idle:
            (frames, timePerFrame) = (animations.idle, animations.idleTimePerFrame)
        case .walk:
            (frames, timePerFrame) = (animations.walk, animations.walkTimePerFrame)
        case .run:
            (frames, timePerFrame) = (animations.run, animations.runTimePerFrame)
        case .jump:
            (frames, timePerFrame) = (animations.jump, animations.jumpTimePerFrame)
        case .attack:
            (frames, timePerFrame) = (animations.attacks.randomElement() ?? [], animations.attackTimePerFrame)
        }
        guard !frames.isEmpty else { return }

        let animate = SKAction.animate(with: frames, timePerFrame: timePerFrame, resize: true, restore: false)
        if action.loops {
            sprite.run(.repeatForever(animate))
        } else {
            sprite.run(.sequence([
                animate,
                .run { [weak self] in
                    self?.play(.idle)
                    self?.onReturnToIdle?()
                },
            ]))
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
    @State private var scene: PetPreviewScene?

    init(entry: PetCatalogEntry, model: PetRosterModel, onBackToLibrary: @escaping () -> Void) {
        self.entry = entry
        self.model = model
        self.onBackToLibrary = onBackToLibrary
        _scene = State(initialValue: entry.kind.map(PetPreviewScene.init))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            stage
            if entry.kind != nil {
                Text("Now playing: \(action.rawValue) (\(action.loops ? "loops" : "plays once, then back to Idle"))")
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
        .onAppear {
            scene?.onReturnToIdle = { action = .idle }
        }
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
            if let scene {
                SpriteView(scene: scene, options: [.allowsTransparency])
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 220)
    }

    private var pills: some View {
        HStack(spacing: 6) {
            ForEach(PetPreviewAction.available(for: entry.kind!)) { pill in
                Button {
                    action = pill
                    scene?.play(pill)
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

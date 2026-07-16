import AppKit

/// A pet region that should capture clicks and hover for the timer feature,
/// in screen coordinates.
struct PetClickTarget {
    let kind: PetKind
    let screenRect: NSRect
    let tooltip: String?
}

/// Click support for pets without giving up the overlay's click-through
/// behavior — the same trick as FileDropController: the overlay stays fully
/// non-interactive, and a small near-invisible panel floats over each
/// timer-enabled pet to catch clicks and show a hover tooltip.
///
/// Panels track roaming pets on a short poll. Pets with a running timer sit
/// still ("focused"), so the steady-state cost is a few rect comparisons.
final class PetClickController {

    var targetsProvider: () -> [PetClickTarget] = { [] }
    /// A pet was clicked. The view is the capture panel's content view,
    /// which doubles as the anchor for the timer popover.
    var onClick: ((PetKind, NSView) -> Void)?

    private var panels: [PetKind: ClickPanel] = [:]
    private var syncTimer: Timer?

    func start() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.sync()
        }
    }

    func stop() {
        syncTimer?.invalidate()
        syncTimer = nil
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    private func sync() {
        let targets = targetsProvider()
        for (kind, panel) in panels where !targets.contains(where: { $0.kind == kind }) {
            panel.orderOut(nil)
            panels[kind] = nil
        }
        for target in targets {
            // Slack so a strolling pet doesn't walk out from under the
            // cursor between polls.
            let rect = target.screenRect.insetBy(dx: -10, dy: -6)
            if let panel = panels[target.kind] {
                if panel.frame != rect {
                    panel.setFrame(rect, display: false)
                }
                panel.contentView?.toolTip = target.tooltip
            } else {
                let kind = target.kind
                let panel = ClickPanel(frame: rect) { [weak self] anchor in
                    self?.onClick?(kind, anchor)
                }
                panel.contentView?.toolTip = target.tooltip
                panel.orderFrontRegardless()
                panels[kind] = panel
            }
        }
    }
}

/// Invisible-but-hit-testable panel over one pet.
private final class ClickPanel: NSPanel {

    init(frame: NSRect, onClick: @escaping (NSView) -> Void) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Above the pet overlay, but below the drag-drop panels (.popUpMenu)
        // so file drops keep working on timer-enabled pets. Drag routing only
        // considers windows registered for the dragged type, so this panel
        // never blocks a drop either way.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        let view = ClickCaptureView(frame: NSRect(origin: .zero, size: frame.size))
        view.onClick = { [weak view] in
            guard let view else { return }
            onClick(view)
        }
        view.autoresizingMask = [.width, .height]
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ClickCaptureView: NSView {

    var onClick: () -> Void = {}

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Nearly invisible but not fully transparent — the window server
        // skips fully transparent windows during hit-testing (same lesson
        // as the drag-drop zones).
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.02).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onClick()
    }

    override func resetCursorRects() {
        // Hover affordance: the pet is clickable even though nothing is drawn.
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

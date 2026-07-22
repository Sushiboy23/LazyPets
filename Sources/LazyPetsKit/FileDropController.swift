import AppKit

/// A pet region that can currently receive a file drop, in screen coordinates.
struct FileDropTarget {
    let id: UUID
    let screenRect: NSRect
}

/// Lets files be dragged onto pets without sacrificing the overlay's
/// click-through behavior.
///
/// The overlay window ignores mouse events entirely, which also opts it out
/// of drag-and-drop — and making it interactive would steal drags/clicks
/// meant for the Dock and Trash behind it. So instead, this controller
/// watches for an in-flight *file* drag (global mouse-dragged events + the
/// drag pasteboard) and, only for the duration of that drag, floats a small
/// invisible drop-accepting panel over each eligible pet, tracking them as
/// they move. The panels vanish when the drag ends, so normal clicks are
/// never intercepted.
final class FileDropController {

    /// Supplies the pets that may accept a drop right now (enabled for the
    /// feature, can attack, overlay visible).
    var targetsProvider: () -> [FileDropTarget] = { [] }
    /// Called when files land on a pet.
    var onDrop: (UUID, [URL]) -> Void = { _, _ in }
    /// Called when a drag starts/stops hovering a pet's drop zone — drives
    /// the pet's warning glow.
    var onHover: (UUID, Bool) -> Void = { _, _ in }

    private var dragMonitor: Any?
    private var upMonitor: Any?
    /// Backstop for ending the session: the global mouse-up monitor only sees
    /// events delivered to *other* apps, so a drop landing on one of our own
    /// drop panels never fires it — which used to strand the drop zones on
    /// screen until some later drag. Polling the button state catches every
    /// end-of-drag path.
    private var cleanupTimer: Timer?
    private var dropWindows: [UUID: DropWindow] = [:]
    private var dragSessionActive = false
    private var lastPasteboardChangeCount = NSPasteboard(name: .drag).changeCount

    func start() {
        dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            self?.handleDragged()
        }
        upMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            self?.endDragSession()
        }
    }

    func stop() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        if let upMonitor { NSEvent.removeMonitor(upMonitor) }
        dragMonitor = nil
        upMonitor = nil
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        removeAllDropWindows()
        dragSessionActive = false
    }

    private func handleDragged() {
        if !dragSessionActive {
            // A new drag pasteboard change count + a file URL on it means a
            // file drag started somewhere (usually Finder).
            let pasteboard = NSPasteboard(name: .drag)
            guard pasteboard.changeCount != lastPasteboardChangeCount,
                  pasteboard.availableType(from: [.fileURL]) != nil else { return }
            dragSessionActive = true
            cleanupTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    self?.endDragSession()
                }
            }
        }
        updateDropWindows()
    }

    private func endDragSession() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        guard dragSessionActive else { return }
        dragSessionActive = false
        lastPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
        // The drop callback (performDragOperation) fires around the same time
        // as the mouse-up; delay teardown so it isn't cut short.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !dragSessionActive else { return }
            removeAllDropWindows()
        }
    }

    private func removeAllDropWindows() {
        for window in dropWindows.values {
            window.orderOut(nil)
        }
        dropWindows.removeAll()
    }

    /// Creates/moves one drop panel per eligible pet; pets keep walking during
    /// a drag, so this is re-run on every dragged event.
    private func updateDropWindows() {
        let targets = targetsProvider()
        for (id, window) in dropWindows where !targets.contains(where: { $0.id == id }) {
            window.orderOut(nil)
            dropWindows[id] = nil
        }
        for target in targets {
            // Give the drop zone some slack around the sprite so users don't
            // need pixel-perfect aim.
            let rect = target.screenRect.insetBy(dx: -12, dy: -12)
            if let window = dropWindows[target.id] {
                window.setFrame(rect, display: true)
            } else {
                let window = DropWindow(
                    frame: rect,
                    onDrop: { [weak self] urls in self?.onDrop(target.id, urls) },
                    onHover: { [weak self] hovering in self?.onHover(target.id, hovering) }
                )
                window.orderFrontRegardless()
                dropWindows[target.id] = window
            }
        }
    }
}

/// Borderless panel that accepts file drops for one pet. It draws a faint
/// outline of the drop zone during the drag (which also gives the window
/// visible pixels — a fully transparent window can be skipped by the
/// system's content-based drag/click hit-testing) and a strong warning glow
/// while a file hovers over it.
private final class DropWindow: NSPanel {

    init(frame: NSRect, onDrop: @escaping ([URL]) -> Void, onHover: @escaping (Bool) -> Void) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu // above the pet overlay and the Dock
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false // accessory app is never "active"; don't self-hide
        // NOT click-through — that's the whole point — but it only exists
        // while a file drag is in flight.

        let dropView = DropView(frame: NSRect(origin: .zero, size: frame.size))
        dropView.onDrop = onDrop
        dropView.onHover = onHover
        dropView.autoresizingMask = [.width, .height]
        contentView = dropView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The actual NSDraggingDestination, with the glow drawing.
private final class DropView: NSView {

    var onDrop: ([URL]) -> Void = { _ in }
    var onHover: (Bool) -> Void = { _ in }

    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            onHover(isHovered)
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        let inset = bounds.insetBy(dx: 3, dy: 3)
        let path = NSBezierPath(roundedRect: inset, xRadius: 10, yRadius: 10)
        path.lineWidth = 2

        if isHovered {
            // Warning glow: release here = pet attacks + file goes to Trash.
            NSColor.systemYellow.withAlphaComponent(0.28).setFill()
            path.fill()
            NSColor.systemYellow.setStroke()
            path.stroke()
        } else {
            // Faint hint that this pet can receive the file (and guarantees
            // the window has visible pixels for drag hit-testing).
            NSColor.systemYellow.withAlphaComponent(0.06).setFill()
            path.fill()
            NSColor.systemYellow.withAlphaComponent(0.35).setStroke()
            path.stroke()
        }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isHovered = true
        return .generic
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isHovered = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        isHovered = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        guard !urls.isEmpty else { return false }
        onDrop(urls)
        return true
    }
}

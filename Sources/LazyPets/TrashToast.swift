import AppKit
import SwiftUI

/// Small corner notification confirming that dropped files went to the Bin.
/// Fades in at the top-right of the screen, lingers briefly, and fades out on
/// its own. Deliberately a plain floating panel rather than a system
/// notification — UNUserNotificationCenter needs a signed bundle and a
/// permission prompt, which is overkill for a passive confirmation.
enum TrashToast {

    private static var window: NSPanel?
    private static var dismissWorkItem: DispatchWorkItem?

    /// Shows the toast, replacing any toast still on screen.
    static func show(message: String) {
        dismissWorkItem?.cancel()
        window?.orderOut(nil)

        let hosting = NSHostingView(rootView: ToastView(message: message))
        hosting.frame.size = hosting.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.frame.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true // purely informational — never steal clicks
        panel.hidesOnDeactivate = false // NSPanel default would hide it if the app deactivates mid-toast
        panel.contentView = hosting

        // Top-right corner, where system notifications appear.
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - panel.frame.width - 16,
                y: visible.maxY - panel.frame.height - 16
            ))
        }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
        window = panel

        let dismiss = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
                if window === panel { window = nil }
            })
        }
        dismissWorkItem = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: dismiss)
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "trash.fill")
                .foregroundStyle(.secondary)
            Text(message)
                .lineLimit(1)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
}

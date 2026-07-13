import AppKit

/// Approximates the Dock's on-screen rect. There's no public API for real Dock
/// geometry, so we infer it from the delta between a screen's full frame and
/// its visibleFrame (the area apps are allowed to use, which excludes the
/// Dock and menu bar).
///
/// This only works cleanly when the Dock is at the bottom of the screen
/// (the default, and the only orientation LazyPets v1 supports) and not
/// auto-hidden. When auto-hidden, visibleFrame ~= full frame, so we fall
/// back to a small fixed strip.
enum DockGeometry {

    static let autoHideFallbackHeight: CGFloat = 6
    static let minimumRealisticHeight: CGFloat = 30

    /// Returns the Dock's frame in screen coordinates for the given screen,
    /// or nil if we can't find a screen at all.
    static func dockRect(on screen: NSScreen? = NSScreen.main) -> NSRect? {
        guard let screen else { return nil }

        let full = screen.frame
        let visible = screen.visibleFrame

        // Bottom inset = space between the true bottom of the screen and the
        // bottom of the visible (usable) area. That's the Dock, when the Dock
        // sits at the bottom edge.
        let bottomInset = visible.minY - full.minY

        let dockHeight = bottomInset >= minimumRealisticHeight
            ? bottomInset
            : autoHideFallbackHeight

        return NSRect(
            x: full.minX,
            y: full.minY,
            width: full.width,
            height: dockHeight
        )
    }

    /// The screen the Dock actually renders on. In multi-display setups this
    /// is usually the screen containing the menu bar, but users can drag the
    /// Dock to any display — NSScreen doesn't expose which, so we default to
    /// `.main` and revisit if this proves wrong in testing.
    static func dockScreen() -> NSScreen? {
        NSScreen.main
    }
}

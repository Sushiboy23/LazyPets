import AppKit

/// Approximates the Dock's on-screen rect. There's no public API for real Dock
/// geometry, so we infer it from the delta between a screen's full frame and
/// its visibleFrame (the area apps are allowed to use, which excludes the
/// Dock and menu bar).
///
/// This only works cleanly when the Dock is at the bottom of the screen
/// (the default, and the only orientation LazyPets v1 supports) and not
/// auto-hidden. When auto-hidden, visibleFrame ~= full frame, so the "Dock"
/// is a zero-height strip and pets stand flush on the screen's bottom edge.
enum DockGeometry {

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
            : 0 // no visible Dock here — pets stand on the screen edge itself

        return NSRect(
            x: full.minX,
            y: full.minY,
            width: full.width,
            height: dockHeight
        )
    }

}

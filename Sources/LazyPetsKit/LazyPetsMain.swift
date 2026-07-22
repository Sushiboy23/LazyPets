import AppKit

/// The app's real entry point, hosted in the library so both launch paths —
/// the SwiftPM executable (dev builds via build_app.sh) and the Xcode app
/// target (App Store / TestFlight builds) — share one `main.swift` that just
/// calls this. The only public symbol in the module.
public enum LazyPetsMain {
    public static func run() -> Never {
        // Plain AppKit app (no SwiftUI @main App struct) so we have full
        // control over activation policy (LSUIElement-style, no Dock icon)
        // and window levels, which SwiftUI's App lifecycle makes awkward.
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate

        // Accessory: no Dock icon, no app switcher entry. Menu bar item is
        // our only chrome.
        app.setActivationPolicy(.accessory)

        app.run()
        exit(0)
    }
}

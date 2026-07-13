import AppKit

// Entry point. This is a plain AppKit app (no SwiftUI @main App struct) so we
// have full control over activation policy (LSUIElement-style, no Dock icon)
// and window levels, which SwiftUI's App lifecycle makes awkward.

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Accessory: no Dock icon, no app switcher entry. Menu bar item is our only chrome.
app.setActivationPolicy(.accessory)

app.run()

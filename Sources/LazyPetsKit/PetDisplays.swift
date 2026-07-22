import AppKit
import SwiftUI

/// A connected physical display, identified by the EDID-derived UUID that
/// macOS itself uses for per-display wallpaper/arrangement. Unlike
/// CGDirectDisplayID or the NSScreen array order, the UUID survives
/// unplug/replug and reconnection into a different port. (Generic no-EDID
/// monitors may get a less stable UUID — known limitation, best effort.)
struct DisplayInfo: Identifiable {
    let uuid: String
    let name: String

    var id: String { uuid }
}

enum ConnectedDisplays {

    static func all() -> [DisplayInfo] {
        NSScreen.screens.compactMap { screen in
            guard let uuid = screen.displayUUID else { return nil }
            return DisplayInfo(uuid: uuid, name: screen.localizedName)
        }
    }

    static func screen(forUUID uuid: String) -> NSScreen? {
        NSScreen.screens.first { $0.displayUUID == uuid }
    }

    static var mainUUID: String? {
        (NSScreen.main ?? NSScreen.screens.first)?.displayUUID
    }
}

extension NSScreen {
    /// NSScreen instances are recreated on configuration changes, so the
    /// display ID from the device description is the durable handle within
    /// one connection session…
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    /// …and the EDID UUID is the handle that survives across sessions.
    var displayUUID: String? {
        guard let displayID,
              let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, cfUUID) as String
    }
}

/// Shared option list for the display-assignment pickers (dropdown popover
/// and the manage window's Displays view): Default, every connected display
/// by name, and — if the current pin is unplugged right now — a placeholder
/// so the selection still displays instead of going blank.
struct DisplayPickerOptions: View {
    let currentPin: String?

    var body: some View {
        Text("Default").tag(String?.none)
        let connected = ConnectedDisplays.all()
        ForEach(connected) { display in
            Text(display.name).tag(String?.some(display.uuid))
        }
        if let pin = currentPin, !connected.contains(where: { $0.uuid == pin }) {
            Text("Disconnected display").tag(String?.some(pin))
        }
    }
}

import AppKit
import UserNotifications

/// Posts the "timer's up" notification with Dismiss / Snooze / New Timer
/// actions and routes those actions back into the app.
///
/// UserNotifications requires a real (signed) app bundle — launched as a
/// bare SwiftPM executable there is no bundle, and even touching
/// `UNUserNotificationCenter.current()` crashes. Everything is therefore
/// gated on the bundle identifier, with the corner toast as the fallback
/// whenever notifications aren't available or authorized.
final class TimerNotifier: NSObject, UNUserNotificationCenterDelegate {

    var onDismiss: ((PetKind) -> Void)?
    var onSnooze: ((PetKind) -> Void)?
    var onNewTimer: ((PetKind) -> Void)?

    private let center: UNUserNotificationCenter? =
        Bundle.main.bundleIdentifier != nil ? .current() : nil
    private var authorized = false
    private var requestedAuthorization = false

    private static let categoryID = "PET_TIMER_DONE"

    func setUp() {
        guard let center else { return }
        center.delegate = self
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [
                UNNotificationAction(identifier: "DISMISS", title: "Dismiss"),
                UNNotificationAction(identifier: "SNOOZE", title: "Snooze +5 min"),
                UNNotificationAction(identifier: "NEW_TIMER", title: "New Timer"),
            ],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])
        // Pick up a grant from a previous session without prompting.
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.authorized = settings.authorizationStatus == .authorized
            }
        }
    }

    /// Called when a timer starts, so the permission prompt appears in
    /// context (first use) instead of at app launch.
    func requestAuthorizationIfNeeded() {
        guard let center, !authorized, !requestedAuthorization else { return }
        requestedAuthorization = true
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.authorized = granted
            }
        }
    }

    func notifyDone(kind: PetKind, note: String) {
        let body = note.isEmpty ? "Timer's up!" : note
        guard let center, authorized else {
            TrashToast.show(message: "\(kind.rawValue): \(body)", systemImage: "alarm.fill")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "\(kind.rawValue) — time's up!"
        content.body = body
        content.categoryIdentifier = Self.categoryID
        content.userInfo = ["petKind": kind.rawValue]
        let request = UNNotificationRequest(
            identifier: "petTimer-\(kind.rawValue)",
            content: content,
            trigger: nil // deliver immediately
        )
        center.add(request) { error in
            if error != nil {
                DispatchQueue.main.async {
                    TrashToast.show(message: "\(kind.rawValue): \(body)", systemImage: "alarm.fill")
                }
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show the banner even while our (background accessory) app is
    /// "frontmost"; no notification sound — the app plays its own,
    /// governed by the "Timer sounds" setting.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        defer { completionHandler() }
        guard let raw = response.notification.request.content.userInfo["petKind"] as? String,
              let kind = PetKind(rawValue: raw) else { return }
        DispatchQueue.main.async { [self] in
            switch response.actionIdentifier {
            case "DISMISS": onDismiss?(kind)
            case "SNOOZE": onSnooze?(kind)
            case "NEW_TIMER": onNewTimer?(kind)
            default: break // plain click — the pet stays in its done state on screen
            }
        }
    }
}

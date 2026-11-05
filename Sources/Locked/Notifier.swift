import AppKit
import Foundation
import UserNotifications
import LockedShared

/// Shows banners even while Locked is the frontmost app.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

@MainActor
enum Notifier {
    private static let presenter = NotificationPresenter()

    /// UNUserNotificationCenter crashes outside an app bundle, so guard on a bundle id.
    private static var canUseNotifications: Bool { Bundle.main.bundleIdentifier != nil }

    static func configure() {
        guard canUseNotifications else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = presenter
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error {
                NSLog("Locked: notification authorization error: %@", String(describing: error))
            }
        }
    }

    static func sessionEnded(outcome: SessionOutcome) {
        _ = NSSound(named: "Glass")?.play()
        guard canUseNotifications else { return }

        let content = UNMutableNotificationContent()
        switch outcome {
        case .completed:
            content.title = "Session complete"
            content.body = "Nice work. Your Locked session is over and all apps are available again."
        case .exitedEarly:
            content.title = "Session ended early"
            content.body = "You used the emergency exit. All apps are available again."
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("Locked: failed to post notification: %@", String(describing: error))
            }
        }
    }
}

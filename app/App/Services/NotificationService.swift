import Foundation
import UserNotifications
import WorkoutCore

/// Schedules the planned countdown / start / finish notifications. Every change replaces all of
/// this app's pending and delivered notifications, so stale ones never remain (判定F).
@MainActor
final class NotificationService {
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func clearAll() async {
        let prefix = NotificationPlan.idPrefix
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    func replace(with plan: [PlannedNotification]) async {
        await clearAll()
        let now = Date()
        for item in plan {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            switch item.sound {
            case .countdown: content.sound = UNNotificationSound(named: UNNotificationSoundName("countdown.wav"))
            case .chime: content.sound = UNNotificationSound(named: UNNotificationSoundName("chime.wav"))
            case .finish: content.sound = UNNotificationSound(named: UNNotificationSoundName("finish.wav"))
            case nil: content.sound = nil
            }
            let delay = max(0.5, item.fireAt.timeIntervalSince(now))
            let request = UNNotificationRequest(identifier: item.id, content: content,
                                                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))
            try? await center.add(request)
        }
    }
}

/// While the app is open the training screen is visible, so play the sound without a banner.
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.sound, .list]
    }
}

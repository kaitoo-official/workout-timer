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

    /// - Parameter keepImminent: for refreshes caused only by time passing (the app is open and a
    ///   step just ended). Notifications due within the next 2 seconds are left alone, so the chime
    ///   for the boundary that is happening right now is not cancelled and re-created too late.
    ///   User actions pass false: everything is replaced, so nothing stale can fire.
    func replace(with plan: [PlannedNotification], keepImminent: Bool) async {
        let prefix = NotificationPlan.idPrefix
        let now = Date()
        let pending = await center.pendingNotificationRequests().filter { $0.identifier.hasPrefix(prefix) }
        var kept = Set<String>()
        if keepImminent {
            for request in pending {
                if let next = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate(),
                   next.timeIntervalSince(now) <= 2 {
                    kept.insert(request.identifier)
                }
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { !kept.contains($0) })
        if !keepImminent {
            let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
            center.removeDeliveredNotifications(withIdentifiers: delivered)
        }
        var added = 0
        for item in plan where !kept.contains(item.id) {
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
            do {
                try await center.add(request)
                added += 1
            } catch {
                DiagnosticsLog.add("通知の予約に失敗：\(item.title) \(error.localizedDescription)")
            }
        }
        let settings = await center.notificationSettings()
        let allowed = settings.authorizationStatus == .authorized ? "" : "（通知が許可されていない）"
        DiagnosticsLog.add("通知：\(added)件予約、直前の\(kept.count)件は維持\(allowed)")
    }
}

/// While the app is open the training screen is visible, so play the sound without a banner.
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.sound, .list]
    }
}

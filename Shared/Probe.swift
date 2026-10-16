import ActivityKit
import AppIntents
import Foundation
import UserNotifications

struct ProbeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var next: String
        var start: Date
        var end: Date
        var paused: Bool
        var remaining: Double
        var repetitions: Bool
    }
    var name: String
}

// Live Activity intents execute in the app process. No app-group storage is required.
struct ProbeSession: Codable {
    var phase = 0
    var start = Date()
    var paused = false
    var remaining: Double = 10
    static let titles = ["休憩", "プランク", "休憩", "腕立て伏せ・15回"]
    static let key = "probe.session.v1"
    static func load() -> Self? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func save() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: Self.key)
    }
    mutating func reconcile(now: Date = Date()) {
        guard !paused else { return }
        while phase < 3 && now >= start.addingTimeInterval(remaining) {
            start = start.addingTimeInterval(remaining)
            remaining = 10
            phase += 1
        }
    }
    var content: ProbeAttributes.ContentState {
        .init(title: Self.titles[phase], next: phase < 3 ? Self.titles[phase + 1] : "完了で終了",
              start: start, end: start.addingTimeInterval(remaining), paused: paused,
              remaining: remaining, repetitions: phase == 3)
    }
}

enum ProbeEngine {
    static let center = UNUserNotificationCenter.current()
    static let notificationIDs = (1...3).map { "probe.boundary.\($0)" }

    static func publish(_ session: ProbeSession) async throws {
        try session.save()
        center.removePendingNotificationRequests(withIdentifiers: notificationIDs)
        center.removeDeliveredNotifications(withIdentifiers: notificationIDs)
        if !session.paused && session.phase < 3 {
            for phase in (session.phase + 1)...3 {
                let date = session.start.addingTimeInterval(session.remaining + Double(phase - session.phase - 1) * 10)
                let delay = date.timeIntervalSinceNow
                guard delay > 0 else { continue }
                let content = UNMutableNotificationContent()
                content.title = ProbeSession.titles[phase]
                content.body = phase == 3 ? "15回。終わったらLive Activityの完了を押す" : "10秒開始（予定時刻の案内）"
                content.sound = .default
                try await center.add(UNNotificationRequest(identifier: "probe.boundary.\(phase)", content: content,
                    trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
            }
        }
        let value = ActivityContent(state: session.content,
            staleDate: session.paused || session.phase == 3 ? nil : session.content.end)
        for activity in Activity<ProbeAttributes>.activities { await activity.update(value) }
    }

    #if !WIDGET_EXTENSION
    static func start() async throws {
        await stop()
        let session = ProbeSession()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw NSError(domain: "Probe", code: 1, userInfo: [NSLocalizedDescriptionKey: "設定でライブアクティビティを許可してください"])
        }
        _ = try Activity.request(attributes: ProbeAttributes(name: "10秒切替の検証"),
            content: ActivityContent(state: session.content, staleDate: session.content.end), pushType: nil)
        do { try await publish(session) } catch { await stop(); throw error }
    }
    #endif

    static func stop() async {
        center.removePendingNotificationRequests(withIdentifiers: notificationIDs)
        center.removeDeliveredNotifications(withIdentifiers: notificationIDs)
        UserDefaults.standard.removeObject(forKey: ProbeSession.key)
        for activity in Activity<ProbeAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    static func action(_ action: String) async throws {
        guard var session = ProbeSession.load() else { return }
        session.reconcile()
        if action == "next" {
            if session.phase == 3 { await stop(); return }
            session.phase += 1
            session.start = Date()
            session.remaining = 10
        } else if session.paused {
            session.paused = false
            session.start = Date()
        } else if session.phase < 3 {
            session.remaining = max(0, session.content.end.timeIntervalSinceNow)
            session.paused = true
        }
        try await publish(session)
    }
}

struct ToggleProbeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "一時停止・再開"
    func perform() async throws -> some IntentResult {
        try await ProbeEngine.action("toggle")
        return .result()
    }
}
struct NextProbeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "次へ・完了"
    func perform() async throws -> some IntentResult {
        try await ProbeEngine.action("next")
        return .result()
    }
}

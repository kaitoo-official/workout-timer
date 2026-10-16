import ActivityKit
import Foundation
import UserNotifications

struct ProbeSession: Codable {
    var mode: ProbeMode
    var plan: ProbePlan
    var index = 0
    var start = Date()
    var paused = false
    var remaining: Double           // timed step: seconds left, counted from `start`
    var completed = 0
    var skipped = 0

    init(mode: ProbeMode, plan: ProbePlan) {
        self.mode = mode
        self.plan = plan
        remaining = plan.steps[0].seconds ?? 0
    }

    static let key = "probe.session.v3"
    static func load() -> Self? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    func save() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: Self.key)
    }

    var steps: [ProbeStep] { plan.steps }
    var step: ProbeStep { steps[index] }
    var end: Date { start.addingTimeInterval(remaining) }

    /// Advances past timed steps whose end has passed. Returns true if the step changed.
    mutating func reconcile(now: Date = Date()) -> Bool {
        guard !paused else { return false }
        var changed = false
        while step.seconds != nil, now >= end, index + 1 < steps.count {
            let boundary = end
            if !step.rest { completed += 1 }
            index += 1
            start = boundary
            remaining = step.seconds ?? 0
            changed = true
        }
        return changed
    }

    struct Segment {
        let index: Int
        let start: Date
        let end: Date
    }

    /// The current step followed by every step that will start automatically:
    /// the chain of timed steps up to and including the first repetition step.
    func upcoming() -> [Segment] {
        var result = [Segment(index: index, start: start, end: end)]
        guard !paused else { return result }
        var i = index
        var t = end
        while steps[i].seconds != nil && i + 1 < steps.count {
            i += 1
            let duration = steps[i].seconds ?? 0
            result.append(Segment(index: i, start: t, end: t.addingTimeInterval(duration)))
            t = t.addingTimeInterval(duration)
        }
        return result
    }

    func state(_ segment: Segment, next: Segment?) -> ProbeAttributes.ContentState {
        let s = steps[segment.index]
        let following = segment.index + 1 < steps.count ? steps[segment.index + 1] : nil
        let isCurrent = segment.index == index
        return .init(
            title: s.title, detail: s.detail,
            start: segment.start, end: max(segment.start, segment.end),
            paused: isCurrent && paused, remaining: isCurrent ? remaining : (s.seconds ?? 0),
            repetitions: s.seconds == nil,
            step: segment.index + 1, stepCount: steps.count,
            nextTitle: following?.title ?? "完了で終了", nextDetail: following?.detail ?? "",
            nextStart: next?.start, nextEnd: next?.end,
            nextRepetitions: following?.seconds == nil)
    }

    /// Rows for mode C: every step that follows on its own, each with its scheduled interval.
    func timeline(_ segments: [Segment]) -> [ProbeAttributes.Row] {
        segments.prefix(4).map { segment in
            let s = steps[segment.index]
            return .init(title: s.title, detail: s.detail, start: segment.start,
                         end: max(segment.start, segment.end), repetitions: s.seconds == nil)
        }
    }

    var summary: String {
        let timing = step.seconds == nil ? "完了待ち" : (paused ? "停止中 残り\(Int(ceil(remaining)))秒" : "残り\(Int(ceil(max(0, end.timeIntervalSinceNow))))秒")
        return "[\(mode.rawValue)/\(plan.rawValue)] \(index + 1)/\(steps.count) \(step.title) \(timing)"
    }
}

enum ProbeLog {
    static let key = "probe.log.v1"
    static var lines: [String] { UserDefaults.standard.stringArray(forKey: key) ?? [] }
    static func add(_ text: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.S"
        var all = lines
        all.append("\(f.string(from: Date())) \(text)")
        UserDefaults.standard.set(Array(all.suffix(300)), forKey: key)
    }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }

    /// Snapshot of what the system holds right now. Recorded on app return so we can tell
    /// whether the Live Activity had already switched before the app ran.
    static func snapshot(_ label: String) async {
        let activities = Activity<ProbeAttributes>.activities.map { a in
            "\(a.attributes.name)=\(a.activityState) 表示:\(a.content.state.step)\(a.content.state.title)"
        }
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(ProbeEngine.prefix) }.count
        add("\(label) LA[\(activities.joined(separator: ", "))] 予約通知\(pending)件")
    }
}

enum ProbeAction { case toggle, next }

enum ProbeEngine {
    static let center = UNUserNotificationCenter.current()
    static let prefix = "probe."
    static let countdownSound = UNNotificationSoundName("countdown5.wav")

    /// Activities that have not been ended. Includes ones scheduled for later (pending).
    static let maxActivities = 5

    static func start(mode: ProbeMode, plan: ProbePlan) async throws {
        await stop(reason: nil)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            throw NSError(domain: "Probe", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "設定でライブアクティビティを許可してください"])
        }
        try await publish(ProbeSession(mode: mode, plan: plan), reason: "開始")
    }

    static func publish(_ session: ProbeSession, reason: String) async throws {
        try session.save()
        await clearNotifications()
        let segments = session.upcoming()
        await scheduleNotifications(session, segments)
        switch session.mode {
        case .single: try await publishSingle(session, segments)
        case .scheduled: try await publishScheduled(session, segments)
        case .timeline: try await publishSingle(session, segments)
        }
        ProbeLog.add("\(reason): \(session.summary)")
    }

    static func stop(reason: String?) async {
        await clearNotifications()
        UserDefaults.standard.removeObject(forKey: ProbeSession.key)
        for activity in Activity<ProbeAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        if let reason { ProbeLog.add(reason) }
    }

    static func action(_ action: ProbeAction, source: String) async {
        guard var session = ProbeSession.load() else {
            ProbeLog.add("\(source)操作: 進行中なし")
            return
        }
        _ = session.reconcile()
        switch action {
        case .next:
            if session.step.seconds == nil { session.completed += 1 }
            else if !session.step.rest { session.skipped += 1 }
            guard session.index + 1 < session.steps.count else {
                await stop(reason: "\(source)操作: 完了で終了（完了\(session.completed) スキップ\(session.skipped)）")
                return
            }
            session.index += 1
            session.start = Date()
            session.remaining = session.step.seconds ?? 0
            session.paused = false
        case .toggle:
            guard session.step.seconds != nil else { return }
            if session.paused {
                session.paused = false
                session.start = Date()
            } else {
                session.remaining = max(0, session.end.timeIntervalSinceNow)
                session.paused = true
            }
        }
        do {
            try await publish(session, reason: "\(source)操作 \(action == .next ? "次へ" : "停止/再開")")
        } catch {
            ProbeLog.add("\(source)操作エラー: \(error.localizedDescription)")
        }
    }

    // MARK: Notifications

    static func clearNotifications() async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(prefix) }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }

    private static func scheduleNotifications(_ session: ProbeSession, _ segments: [ProbeSession.Segment]) async {
        guard !session.paused else { return }
        for segment in segments.dropFirst() {
            let step = session.steps[segment.index]
            let countdownAt = segment.start.addingTimeInterval(-5).timeIntervalSinceNow
            if countdownAt > 0.5 {
                let content = UNMutableNotificationContent()
                content.title = "5秒前：次は\(step.title)"
                content.body = step.detail
                content.sound = UNNotificationSound(named: countdownSound)
                await add("\(prefix)cd.\(segment.index)", content, after: countdownAt)
            }
            // Mode B announces each boundary with the scheduled Live Activity's own alert.
            if session.mode != .scheduled {
                let at = segment.start.timeIntervalSinceNow
                guard at > 0.5 else { continue }
                let content = UNMutableNotificationContent()
                content.title = "開始：\(step.title)"
                content.body = step.seconds == nil ? "\(step.detail)。終わったら完了を押す" : step.detail
                content.sound = .default
                await add("\(prefix)b.\(segment.index)", content, after: at)
            }
        }
    }

    private static func add(_ id: String, _ content: UNMutableNotificationContent, after delay: TimeInterval) async {
        do {
            try await center.add(UNNotificationRequest(identifier: id, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)))
        } catch {
            ProbeLog.add("通知予約エラー \(id): \(error.localizedDescription)")
        }
    }

    // MARK: Live Activities

    private static func staleDate(_ session: ProbeSession, _ segment: ProbeSession.Segment) -> Date? {
        let isCurrent = segment.index == session.index
        if isCurrent && session.paused { return nil }
        return session.steps[segment.index].seconds == nil ? nil : segment.end
    }

    /// Modes A and C: a single activity. The app updates it whenever it runs. Between updates,
    /// A relies on the stale date (one switch at most) and C on per-row system timers.
    private static func publishSingle(_ session: ProbeSession, _ segments: [ProbeSession.Segment]) async throws {
        let current = segments[0]
        var state = session.state(current, next: segments.dropFirst().first)
        if session.mode == .timeline && !session.paused { state.timeline = session.timeline(segments) }
        let content = ActivityContent(state: state,
                                      staleDate: session.mode == .single ? staleDate(session, current) : nil)
        let live = Activity<ProbeAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
        if let activity = live.first {
            await activity.update(content)
            for extra in live.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else {
            _ = try Activity.request(attributes: ProbeAttributes(name: session.mode == .single ? "A" : "C", mode: session.mode.rawValue),
                                     content: content, pushType: nil)
        }
    }

    /// Mode B (iOS 26+): end everything, then start the current step now and schedule one
    /// activity per following automatic step. The system starts each at its date even when
    /// the app is not running. Count/limit failures are logged, not hidden.
    private static func publishScheduled(_ session: ProbeSession, _ segments: [ProbeSession.Segment]) async throws {
        for activity in Activity<ProbeAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        // The system rejects requests beyond its per-app limit (5 seen on iOS 26.6.2), pending ones included.
        for (k, segment) in segments.prefix(maxActivities).enumerated() {
            let next = k + 1 < segments.count ? segments[k + 1] : nil
            let content = ActivityContent(state: session.state(segment, next: next),
                                          staleDate: staleDate(session, segment),
                                          relevanceScore: Double(100 - k))
            let attributes = ProbeAttributes(name: "B\(segment.index + 1)", mode: ProbeMode.scheduled.rawValue)
            if k == 0 {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                continue
            }
            guard #available(iOS 26.0, *) else {
                ProbeLog.add("予約LAはiOS 26以降のみ")
                break
            }
            let step = session.steps[segment.index]
            let alert = AlertConfiguration(title: "\(step.title)", body: "\(step.detail)", sound: .default)
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil,
                                         style: .standard, alertConfiguration: alert, start: segment.start)
            } catch {
                ProbeLog.add("予約LA失敗 \(segment.index + 1)番目（\(k)件予約済み）: \(error.localizedDescription)")
                break
            }
        }
    }
}

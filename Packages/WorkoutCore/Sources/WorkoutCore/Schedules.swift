import Foundation

/// A step with its projected times. `end` is nil for a step that waits for the user.
public struct TimelineEntry: Equatable, Sendable {
    public let step: Step
    public let start: Date?
    public let end: Date?
}

extension Session {
    /// The current step and the steps that will follow on their own, with projected times.
    /// Only a running step can lead anywhere without the user; paused, waiting and finished
    /// sessions return just the current step (or nothing). Call `advance(to:)` first.
    public func projectedChain() -> [TimelineEntry] {
        guard let current = currentStep else { return [] }
        guard case .running(let startedAt, let endAt) = phase else {
            return [TimelineEntry(step: current, start: nil, end: nil)]
        }
        let plan = self.plan
        let indices = plan.autoChain(from: stepIndex)
        var entries = [TimelineEntry(step: current, start: startedAt, end: endAt)]
        var cursor = endAt
        for index in indices.dropFirst() {
            let step = plan.steps[index]
            if step.endsAutomatically && !step.startsManually, let s = step.seconds {
                let end = cursor.addingTimeInterval(TimeInterval(s))
                entries.append(TimelineEntry(step: step, start: cursor, end: end))
                cursor = end
            } else {
                entries.append(TimelineEntry(step: step, start: cursor, end: nil))
            }
        }
        return entries
    }

    /// True when the projected chain runs to the end of the workout on time.
    func chainReachesEnd(_ chain: [TimelineEntry]) -> Bool {
        guard let last = chain.last else { return false }
        return last.end != nil && last.step.index == plan.steps.count - 1
    }
}

// MARK: - Live Activities (docs/動作ルール.md §7)

public enum ActivityPlan: Equatable, Sendable {
    case none
    /// One activity per step: the first starts now, the rest are scheduled at their start time.
    case perStep([TimelineEntry])
    /// One activity listing the chain as rows (used when scheduling is not possible).
    case block([TimelineEntry])

    /// - Parameters:
    ///   - foreground: the app is active (scheduling future activities is allowed).
    ///   - capacity: activities that may exist at once for this plan; keep one slot free.
    public static func make(for session: Session, foreground: Bool,
                            capacity: Int = LiveActivityLimits.chainRows) -> ActivityPlan {
        let chain = session.projectedChain()
        guard !chain.isEmpty else { return .none }
        if chain.count == 1 { return .perStep(chain) }
        if foreground { return .perStep(Array(chain.prefix(max(1, capacity)))) }
        return .block(Array(chain.prefix(LiveActivityLimits.chainRows)))
    }

    /// What to show after scheduling `succeeded` of the per-step items: if any failed, fall
    /// back to a block so the display never stops while notifications keep coming.
    public func afterScheduling(succeeded: Int) -> ActivityPlan {
        guard case .perStep(let entries) = self, succeeded < entries.count else { return self }
        return entries.count == 1 ? self : .block(Array(entries.prefix(LiveActivityLimits.chainRows)))
    }
}

// MARK: - Notifications (docs/動作ルール.md §8)

public struct SoundSettings: Codable, Equatable, Sendable {
    /// Short beeps during the last 5 seconds before a step starts.
    public var preannounce = true
    /// Chime when a step starts (second 0).
    public var start = true
    /// Sound when the workout ends on time.
    public var finish = true
    /// In-app haptics.
    public var haptics = true

    public init() {}
}

public struct PlannedNotification: Equatable, Sendable {
    public enum Kind: String, Sendable { case countdown, start, finishCountdown, finish }
    public enum Sound: String, Sendable { case countdown, chime, finish }

    public let id: String
    public let kind: Kind
    public let stepIndex: Int
    public let fireAt: Date
    public let title: String
    public let body: String
    /// nil = silent banner.
    public let sound: Sound?
}

public enum NotificationPlan {
    public static let idPrefix = "wt."
    /// iOS keeps at most 64 pending requests per app.
    public static let maxPending = 60

    public static func make(for session: Session, at now: Date, settings: SoundSettings) -> [PlannedNotification] {
        guard !session.isFinished else { return [] }
        let chain = session.projectedChain()
        guard chain.count > 0, case .running = session.phase else { return [] }
        let tag = idPrefix + session.id.uuidString.prefix(8)
        let rounds = session.plan.rounds
        var result: [PlannedNotification] = []

        func add(_ kind: PlannedNotification.Kind, _ step: Step, _ at: Date, _ title: String, _ body: String,
                 _ sound: PlannedNotification.Sound?) {
            guard at.timeIntervalSince(now) > 0.5 else { return }
            result.append(PlannedNotification(id: "\(tag).\(step.index).\(kind.rawValue)", kind: kind,
                                              stepIndex: step.index, fireAt: at, title: title, body: body, sound: sound))
        }

        for entry in chain.dropFirst() {
            guard let start = entry.start else { continue }
            let step = entry.step
            let roundNote = rounds > 1 ? "（\(step.round)/\(rounds)周）" : ""
            if settings.preannounce {
                add(.countdown, step, start.addingTimeInterval(-5), "5秒前：次は\(step.title)",
                    step.amountLabel + roundNote, .countdown)
            }
            let body: String
            if step.reps != nil { body = "\(step.amountLabel)。終わったら完了を押す" }
            else if step.startsManually { body = "\(step.amountLabel)。準備できたら開始を押す" }
            else { body = step.amountLabel }
            add(.start, step, start, "開始：\(step.title)", body + roundNote, settings.start ? .chime : nil)
        }

        if session.chainReachesEnd(chain), let last = chain.last, let end = last.end {
            if settings.preannounce {
                add(.finishCountdown, last.step, end.addingTimeInterval(-5), "5秒前：まもなく終了", last.step.title, .countdown)
            }
            add(.finish, last.step, end, "終了：おつかれさまでした", session.menu.name, settings.finish ? .finish : nil)
        }
        return Array(result.sorted { $0.fireAt < $1.fireAt }.prefix(maxPending))
    }
}

import ActivityKit
import Foundation
import WorkoutCore

/// Turns an ActivityPlan into Live Activities, using only what the probe proved on device:
/// immediate + scheduled (iOS 26 `start:`) requests in the foreground, a block activity when
/// scheduling is not possible, and ending finished steps when a scheduled one begins.
@MainActor
final class LiveActivityService {
    typealias Content = WorkoutActivityAttributes.ContentState

    /// Called with the first step index of an activity that just became active.
    var onActivated: ((Int) -> Void)?
    private var observing = false
    private var watched = Set<String>()

    func startObserving() {
        guard !observing else { return }
        observing = true
        Task {
            for activity in Activity<WorkoutActivityAttributes>.activities { watch(activity) }
            for await activity in Activity<WorkoutActivityAttributes>.activityUpdates { watch(activity) }
        }
    }

    private func watch(_ activity: Activity<WorkoutActivityAttributes>) {
        guard watched.insert(activity.id).inserted else { return }
        Task {
            for await state in activity.activityStateUpdates where state == .active {
                // The app may only get a moment in the background here (30–75 ms on device), so
                // end finished steps first, in this task, before anything else.
                let first = activity.content.state.firstStep
                var ended = 0
                for other in Activity<WorkoutActivityAttributes>.activities
                where other.id != activity.id && other.content.state.lastStep < first {
                    await other.end(nil, dismissalPolicy: .immediate)
                    ended += 1
                }
                DiagnosticsLog.add("LA開始 区間\(first + 1)：終わった表示を\(ended)件閉じた")
                onActivated?(first)
            }
        }
    }

    func endAll() async {
        for activity in Activity<WorkoutActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func endActivities(before step: Int) async {
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.content.state.lastStep < step {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func apply(_ plan: ActivityPlan, session: Session) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            DiagnosticsLog.add("LA：ライブアクティビティが許可されていない")
            return
        }
        await endAll()
        switch plan {
        case .none:
            return
        case .block(let rows):
            requestBlock(rows, session: session)
            DiagnosticsLog.add("LA：まとめ表示 \(rows.count)行")
        case .perStep(let entries):
            var succeeded = 0
            for (k, entry) in entries.enumerated() {
                do {
                    try requestSingle(entry, session: session, scheduled: k > 0)
                    succeeded += 1
                } catch {
                    break
                }
            }
            // Partial success (device or OS allows fewer than planned): fall back to one block
            // so the display keeps progressing while notifications fire.
            let adjusted = plan.afterScheduling(succeeded: succeeded)
            if adjusted != plan, case .block(let rows) = adjusted {
                await endAll()
                requestBlock(rows, session: session)
                DiagnosticsLog.add("LA：予約\(entries.count)件中\(succeeded)件のみ成功 → まとめ表示に切替")
            } else {
                DiagnosticsLog.add("LA：区間ごとに\(succeeded)件（\(entries.first.map { "区間\($0.step.index + 1)" } ?? "")から）")
            }
        }
    }

    // MARK: Content

    private func attributes(_ session: Session) -> WorkoutActivityAttributes {
        WorkoutActivityAttributes(menuName: session.menu.name, sessionID: session.id.uuidString)
    }

    private func row(_ entry: TimelineEntry) -> WorkoutActivityAttributes.Row {
        .init(stepIndex: entry.step.index, title: entry.step.title, detail: entry.step.amountLabel,
              isRest: entry.step.isRest, start: entry.start, end: entry.end, waitsForStart: entry.step.startsManually)
    }

    private func nextLabel(after step: Step, in plan: Plan) -> String {
        guard step.index + 1 < plan.steps.count else { return "" }
        let next = plan.steps[step.index + 1]
        if next.isRest, let after = plan.nextExercise(after: next.index) {
            return "\(next.title) → \(after.title) \(after.amountLabel)"
        }
        return "\(next.title) \(next.amountLabel)"
    }

    private func requestSingle(_ entry: TimelineEntry, session: Session, scheduled: Bool) throws {
        let plan = session.plan
        let isCurrent = entry.step.index == session.stepIndex
        var paused = false
        var remaining: Double?
        if isCurrent, case .paused(let r) = session.phase { paused = true; remaining = r }
        let state = Content(kind: .single, rows: [row(entry)], round: entry.step.round, rounds: plan.rounds,
                            next: nextLabel(after: entry.step, in: plan), paused: paused, pausedRemaining: remaining,
                            firstStep: entry.step.index, lastStep: entry.step.index)
        let content = ActivityContent(state: state, staleDate: nil, relevanceScore: Double(entry.step.index + 1))
        if scheduled, let start = entry.start {
            let alert = AlertConfiguration(title: "\(entry.step.title)", body: "\(entry.step.amountLabel)",
                                           sound: .named("silent.wav"))
            _ = try Activity.request(attributes: attributes(session), content: content, pushType: nil,
                                     style: .standard, alertConfiguration: alert, start: start)
        } else {
            _ = try Activity.request(attributes: attributes(session), content: content, pushType: nil)
        }
    }

    private func requestBlock(_ entries: [TimelineEntry], session: Session) {
        guard let first = entries.first, let last = entries.last else { return }
        let state = Content(kind: .block, rows: entries.map(row), round: first.step.round, rounds: session.plan.rounds,
                            next: "", paused: false, pausedRemaining: nil,
                            firstStep: first.step.index, lastStep: last.step.index)
        _ = try? Activity.request(attributes: attributes(session),
                                  content: ActivityContent(state: state, staleDate: nil, relevanceScore: 100),
                                  pushType: nil)
    }
}

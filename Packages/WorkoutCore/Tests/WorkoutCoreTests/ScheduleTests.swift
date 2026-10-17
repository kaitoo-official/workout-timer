import XCTest
@testable import WorkoutCore

final class ScheduleTests: XCTestCase {
    /// Push-ups completed at t0+10 → rest 10…30 → plank 30…50 → rest 50…70 → squat waits from 70.
    func runningMixed() -> Session {
        var s = Session(menu: mixedMenu, at: t0)
        s.apply(.complete, at: at(10))
        return s
    }

    func testProjectedChainTimes() {
        let chain = runningMixed().projectedChain()
        XCTAssertEqual(chain.map(\.step.title), ["休憩", "プランク", "休憩", "スクワット"])
        XCTAssertEqual(chain.map(\.start), [at(10), at(30), at(50), at(70)])
        XCTAssertEqual(chain.map(\.end), [at(30), at(50), at(70), nil])
    }

    func testWaitingAndPausedProjectOnlyCurrent() {
        var s = Session(menu: mixedMenu, at: t0)
        XCTAssertEqual(s.projectedChain().count, 1)
        s.apply(.complete, at: at(0))
        s.apply(.pause, at: at(3))
        XCTAssertEqual(s.projectedChain().map(\.step.title), ["休憩"])
    }

    func testActivityPlanForegroundSchedulesEachStep() {
        guard case .perStep(let items) = ActivityPlan.make(for: runningMixed(), foreground: true) else {
            return XCTFail("expected perStep")
        }
        XCTAssertEqual(items.count, 4)
        guard case .perStep(let capped) = ActivityPlan.make(for: runningMixed(), foreground: true, capacity: 2) else {
            return XCTFail("expected perStep")
        }
        XCTAssertEqual(capped.count, 2)
    }

    func testActivityPlanBackgroundUsesBlock() {
        guard case .block(let rows) = ActivityPlan.make(for: runningMixed(), foreground: false) else {
            return XCTFail("expected block")
        }
        XCTAssertEqual(rows.map(\.step.title), ["休憩", "プランク", "休憩", "スクワット"])
        // A single waiting step is shown as one activity even from the background.
        let waiting = Session(menu: mixedMenu, at: t0)
        XCTAssertEqual(ActivityPlan.make(for: waiting, foreground: false), .perStep(waiting.projectedChain()))
    }

    func testPartialSchedulingFallsBackToBlock() {
        let plan = ActivityPlan.make(for: runningMixed(), foreground: true)
        XCTAssertEqual(plan.afterScheduling(succeeded: 4), plan)
        guard case .block(let rows) = plan.afterScheduling(succeeded: 2) else { return XCTFail("expected block") }
        XCTAssertEqual(rows.count, 4)
        let finished: Session = { var s = Session(menu: mixedMenu, at: t0); s.apply(.finish, at: at(1)); return s }()
        XCTAssertEqual(ActivityPlan.make(for: finished, foreground: true), .none)
    }

    func testNotificationsForChain() {
        let s = runningMixed()
        let list = NotificationPlan.make(for: s, at: at(10), settings: SoundSettings())
        XCTAssertEqual(list.map(\.fireAt), [at(25), at(30), at(45), at(50), at(65), at(70)])
        XCTAssertEqual(list.map(\.kind), [.countdown, .start, .countdown, .start, .countdown, .start])
        XCTAssertEqual(Set(list.map(\.id)).count, list.count, "ids must be unique")
        XCTAssertTrue(list.allSatisfy { $0.id.hasPrefix(NotificationPlan.idPrefix) })
        XCTAssertEqual(list.last?.title, "開始：スクワット")
        XCTAssertEqual(list.last?.sound, .chime)
        // Past times are not scheduled.
        XCTAssertEqual(NotificationPlan.make(for: s, at: at(46), settings: SoundSettings()).map(\.fireAt),
                       [at(50), at(65), at(70)])
    }

    func testNotificationSettings() {
        var settings = SoundSettings()
        settings.preannounce = false
        settings.start = false
        let list = NotificationPlan.make(for: runningMixed(), at: at(10), settings: settings)
        XCTAssertTrue(list.allSatisfy { $0.kind == .start && $0.sound == nil }, "silent start banners only")
    }

    func testNoNotificationsWhilePausedOrWaiting() {
        var s = runningMixed()
        s.apply(.pause, at: at(12))
        XCTAssertEqual(NotificationPlan.make(for: s, at: at(12), settings: SoundSettings()), [])
        XCTAssertEqual(NotificationPlan.make(for: Session(menu: mixedMenu, at: t0), at: t0, settings: SoundSettings()), [])
    }

    func testFinishNotificationWhenChainReachesEnd() {
        var s = Session(menu: menu([reps("腕立て伏せ", 10), timed("プランク", 20)]), at: t0)
        s.apply(.complete, at: at(0))                    // rest 0…20, plank 20…40, end
        let list = NotificationPlan.make(for: s, at: at(0), settings: SoundSettings())
        XCTAssertEqual(list.suffix(2).map(\.kind), [.finishCountdown, .finish])
        XCTAssertEqual(list.last?.fireAt, at(40))
        XCTAssertEqual(list.last?.sound, .finish)
    }
}

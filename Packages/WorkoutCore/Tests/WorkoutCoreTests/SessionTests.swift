import XCTest
@testable import WorkoutCore

final class SessionTests: XCTestCase {
    func testRepetitionStepNeverCompletesOnItsOwn() {
        var s = Session(menu: mixedMenu, at: t0)
        XCTAssertEqual(s.phase, .waitingCompletion(since: t0))
        XCTAssertFalse(s.advance(to: at(3600)))
        XCTAssertEqual(s.stepIndex, 0)
        XCTAssertEqual(s.completedExercises, 0)
    }

    func testTimedChainUsesScheduledEndTimesWithoutDrift() {
        var s = Session(menu: mixedMenu, at: t0)
        XCTAssertNil(s.apply(.complete, target: .step(0), at: at(10)))
        XCTAssertEqual(s.phase, .running(startedAt: at(10), endAt: at(30)))   // rest 20
        // App was away for a long time: rest and plank both ended; squat waits.
        s.advance(to: at(95))
        XCTAssertEqual(s.stepIndex, 4)
        XCTAssertEqual(s.phase, .waitingCompletion(since: at(70)))          // 10+20+20+20, not 95
        XCTAssertEqual(s.completedExercises, 2)                              // push-ups + plank
    }

    func testPauseResumeKeepsRemainingTime() {
        var s = Session(menu: mixedMenu, at: t0)
        s.apply(.complete, at: at(0))
        s.apply(.pause, at: at(5))
        XCTAssertEqual(s.phase, .paused(remaining: 15))
        s.advance(to: at(500))
        XCTAssertEqual(s.stepIndex, 1, "paused steps do not advance")
        s.apply(.resume, at: at(500))
        XCTAssertEqual(s.phase, .running(startedAt: at(500), endAt: at(515)))
    }

    func testExtendRestOnlyOnRests() {
        var s = Session(menu: mixedMenu, at: t0)
        XCTAssertEqual(s.apply(.extendRest, at: at(1)), .notAllowed)
        s.apply(.complete, at: at(0))
        XCTAssertNil(s.apply(.extendRest, at: at(5), extendBy: 30))
        XCTAssertEqual(s.phase, .running(startedAt: at(0), endAt: at(50)))
    }

    func testSkipDoesNotCountAsCompletion() {
        var s = Session(menu: mixedMenu, at: t0)
        s.apply(.skip, at: at(1))
        XCTAssertEqual(s.skippedExercises, 1)
        XCTAssertEqual(s.completedExercises, 0)
        XCTAssertEqual(s.stepIndex, 1)
        s.apply(.skip, at: at(2))               // skipping a rest is not an exercise skip
        XCTAssertEqual(s.skippedExercises, 1)
        XCTAssertEqual(s.currentStep?.title, "プランク")
    }

    func testDuplicateTapIsIgnored() {
        var s = Session(menu: mixedMenu, at: t0)
        XCTAssertNil(s.apply(.complete, target: .step(0), at: at(1)))
        XCTAssertEqual(s.apply(.complete, target: .step(0), at: at(1.2)), .staleTarget)
        XCTAssertEqual(s.stepIndex, 1)
        // A block display covering steps 1...4 still acts on the current step.
        XCTAssertNil(s.apply(.next, target: .range(1...4), at: at(2)))
        XCTAssertEqual(s.stepIndex, 2)
        // A tap from an older block (0...1) is ignored.
        XCTAssertEqual(s.apply(.next, target: .range(0...1), at: at(3)), .staleTarget)
    }

    func testNextCompletesWhenWaitingAndSkipsOtherwise() {
        var s = Session(menu: mixedMenu, at: t0)
        s.apply(.next, at: at(1))
        XCTAssertEqual(s.completedExercises, 1)
        s.apply(.next, at: at(2))
        XCTAssertEqual(s.currentStep?.title, "プランク")
        XCTAssertEqual(s.skippedExercises, 0)
    }

    func testUndoRestoresStepAndRemainingTime() {
        var s = Session(menu: mixedMenu, at: t0)
        s.apply(.complete, at: at(0))           // rest 0...20
        s.apply(.skip, at: at(5))               // 15s were left
        XCTAssertEqual(s.currentStep?.title, "プランク")
        XCTAssertNil(s.apply(.undo, at: at(100)))
        XCTAssertEqual(s.stepIndex, 1)
        XCTAssertEqual(s.phase, .running(startedAt: at(95), endAt: at(115)))
        XCTAssertNil(s.apply(.undo, at: at(101)))
        XCTAssertEqual(s.stepIndex, 0)
        XCTAssertEqual(s.completedExercises, 0)
        XCTAssertEqual(s.phase, .waitingCompletion(since: at(101)))
        XCTAssertEqual(s.apply(.undo, at: at(102)), .nothingToUndo)
    }

    func testManualStartWaits() {
        var s = Session(menu: menu([timed("プランク", 30)], autoStart: false), at: t0)
        XCTAssertEqual(s.phase, .waitingStart)
        s.advance(to: at(999))
        XCTAssertEqual(s.phase, .waitingStart)
        s.apply(.start, at: at(10))
        s.advance(to: at(40))
        XCTAssertEqual(s.ending, .completed)
        XCTAssertEqual(s.endedAt, at(40))
        XCTAssertEqual(s.completedExercises, 1)
    }

    func testFinishAndActionsAfterFinish() {
        var s = Session(menu: mixedMenu, at: t0)
        XCTAssertNil(s.apply(.finish, at: at(3)))
        XCTAssertEqual(s.ending, .aborted)
        XCTAssertEqual(s.apply(.complete, at: at(4)), .finished)
        XCTAssertFalse(s.canUndo)
    }

    func testCompletingLastStepEndsSession() {
        var s = Session(menu: menu([reps("腕立て伏せ", 10)]), at: t0)
        s.apply(.complete, at: at(5))
        XCTAssertEqual(s.ending, .completed)
        XCTAssertNil(s.currentStep)
    }

    func testUndoDepthIsBounded() {
        var s = Session(menu: menu(Array(repeating: reps("x", 1), count: 30), rest: 0), at: t0)
        for i in 0..<25 { s.apply(.complete, at: at(Double(i))) }
        var undone = 0
        while s.apply(.undo, at: at(100)) == nil { undone += 1 }
        XCTAssertEqual(undone, Session.undoDepth)
    }

    func testCodableRoundTrip() throws {
        var s = Session(menu: mixedMenu, at: t0)
        s.apply(.complete, at: at(1))
        let data = try FileStore.encoder.encode(s)
        XCTAssertEqual(try FileStore.decoder.decode(Session.self, from: data), s)
    }
}

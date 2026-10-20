import XCTest
@testable import WorkoutCore

final class DurationTests: XCTestCase {
    func testBoundaryConversions() {
        XCTAssertEqual(MinutesSeconds(totalSeconds: 0), MinutesSeconds(minutes: 0, seconds: 0))
        XCTAssertEqual(MinutesSeconds(totalSeconds: 59), MinutesSeconds(minutes: 0, seconds: 59))
        XCTAssertEqual(MinutesSeconds(totalSeconds: 60), MinutesSeconds(minutes: 1, seconds: 0))
        XCTAssertEqual(MinutesSeconds(totalSeconds: 90), MinutesSeconds(minutes: 1, seconds: 30))
        XCTAssertEqual(MinutesSeconds(totalSeconds: 1800), MinutesSeconds(minutes: 30, seconds: 0))
        XCTAssertEqual(MinutesSeconds(totalSeconds: 3600), MinutesSeconds(minutes: 60, seconds: 0))
        XCTAssertEqual(MinutesSeconds(totalSeconds: -5), MinutesSeconds(minutes: 0, seconds: 0))
    }

    func testRoundTripForEveryAllowedValue() {
        for s in 0...3600 {
            XCTAssertEqual(MinutesSeconds(totalSeconds: s).totalSeconds, s)
        }
    }

    func testExerciseLimits() {
        let f = DurationField.exercise
        XCTAssertFalse(f.isValid(MinutesSeconds(minutes: 0, seconds: 0)), "0 seconds is not a timed exercise")
        XCTAssertTrue(f.isValid(MinutesSeconds(minutes: 0, seconds: 1)))
        XCTAssertTrue(f.isValid(MinutesSeconds(minutes: 60, seconds: 0)))
        XCTAssertFalse(f.isValid(MinutesSeconds(minutes: 60, seconds: 1)))
        XCTAssertEqual(f.minuteRange, 0...60)
        XCTAssertEqual(f.secondRange(forMinutes: 59), 0...59)
        XCTAssertEqual(f.secondRange(forMinutes: 60), 0...0)
    }

    func testRestLimits() {
        let f = DurationField.rest
        XCTAssertTrue(f.isValid(MinutesSeconds(minutes: 0, seconds: 0)), "0 means no rest step")
        XCTAssertTrue(f.isValid(MinutesSeconds(minutes: 30, seconds: 0)))
        XCTAssertFalse(f.isValid(MinutesSeconds(minutes: 30, seconds: 1)))
        XCTAssertEqual(f.minuteRange, 0...30)
        XCTAssertEqual(f.secondRange(forMinutes: 30), 0...0)
    }

    func testAdjustedClampsSecondsAtTopMinute() {
        XCTAssertEqual(DurationField.rest.adjusted(MinutesSeconds(minutes: 30, seconds: 45)),
                       MinutesSeconds(minutes: 30, seconds: 0))
        XCTAssertEqual(DurationField.exercise.adjusted(MinutesSeconds(minutes: 2, seconds: 45)),
                       MinutesSeconds(minutes: 2, seconds: 45))
        XCTAssertEqual(DurationField.rest.adjusted(MinutesSeconds(minutes: 99, seconds: 10)),
                       MinutesSeconds(minutes: 30, seconds: 0))
    }
}

import XCTest
@testable import WorkoutCore

final class MenuAndPlanTests: XCTestCase {
    func testAmountJSONShape() throws {
        let data = try JSONEncoder().encode(Amount.reps(15))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["type"] as? String, "reps")
        XCTAssertEqual(object?["value"] as? Int, 15)
        XCTAssertEqual(try JSONDecoder().decode(Amount.self, from: Data(#"{"type":"seconds","value":30}"#.utf8)), .seconds(30))
        XCTAssertThrowsError(try JSONDecoder().decode(Amount.self, from: Data(#"{"type":"meters","value":3}"#.utf8)))
    }

    func testValidation() {
        XCTAssertEqual(PersonalMenus.chest().validate(), [])
        var bad = menu([reps(" ", 0)], rounds: 0, rest: -1)
        bad.name = ""
        let issues = bad.validate()
        XCTAssertTrue(issues.contains(.emptyName))
        XCTAssertTrue(issues.contains(.roundsOutOfRange))
        XCTAssertTrue(issues.contains(.restOutOfRange))
        XCTAssertTrue(issues.contains(.exerciseNameEmpty(index: 0)))
        XCTAssertTrue(issues.contains(.amountOutOfRange(index: 0)))
        XCTAssertTrue(menu([]).validate().contains(.noExercises))
    }

    func testChestPlanOrderAndRests() {
        let plan = Plan(menu: PersonalMenus.chest())
        // 9 exercises, 2 rests per round, 2 between-rounds rests, nothing after the last exercise.
        XCTAssertEqual(plan.steps.count, 17)
        XCTAssertEqual(plan.steps.map(\.title).prefix(7),
                       ["ノーマル", "休憩", "デクライン", "休憩", "ナロー", "周回間休憩", "ノーマル"])
        XCTAssertEqual(plan.steps[5].kind, .roundRest)
        XCTAssertEqual(plan.steps[5].seconds, 90)
        XCTAssertEqual(plan.steps[6].round, 2)
        XCTAssertEqual(plan.steps.last?.title, "ナロー")
        XCTAssertEqual(plan.steps.last?.round, 3)
        XCTAssertEqual(plan.steps.map(\.index), Array(0..<17))
    }

    func testRestOverrideZeroRestAndManualStart() {
        let m = menu([timed("プランク", 30, rest: 15), reps("腹筋", 20, rest: 0), reps("背筋", 10, rest: 5)],
                     rounds: 2, rest: 60, roundRest: 90, autoStart: false)
        let plan = Plan(menu: m)
        let titles = plan.steps.map { "\($0.title)\($0.seconds.map { "\($0)" } ?? "")" }
        // Override 15 after plank, no rest after 腹筋 (0), round rest (not override 5) after 背筋.
        XCTAssertEqual(titles, ["プランク30", "休憩15", "腹筋", "背筋", "周回間休憩90",
                                "プランク30", "休憩15", "腹筋", "背筋"])
        XCTAssertTrue(plan.steps[0].startsManually)
        XCTAssertFalse(plan.steps[2].startsManually)
        XCTAssertFalse(plan.steps[2].endsAutomatically)
    }
}

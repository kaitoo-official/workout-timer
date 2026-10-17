import XCTest
@testable import WorkoutCore

/// The three examples in docs/動作ルール.md §6.
final class AutoChainTests: XCTestCase {
    func titles(_ check: AutoProgressCheck) -> [String] { check.longestChain.map(\.title) }

    func testChestRepetitionsOnly() {
        let check = AutoProgressCheck(menu: PersonalMenus.chest())
        XCTAssertEqual(check.longestChain.count, 2)
        XCTAssertTrue(check.isAllowed)
    }

    func testPersonalMenusAllPass() {
        for m in PersonalMenus.all() {
            XCTAssertTrue(AutoProgressCheck(menu: m).isAllowed, m.name)
            XCTAssertEqual(m.validate(), [], m.name)
        }
    }

    func testMixedFourRowsPass() {
        let check = AutoProgressCheck(menu: mixedMenu)
        XCTAssertEqual(titles(check), ["休憩", "プランク", "休憩", "スクワット"])
        XCTAssertTrue(check.isAllowed)
    }

    func testLongTimedChainIsRejectedAndManualVariantPasses() {
        let check = AutoProgressCheck(menu: longTimedMenu)
        XCTAssertEqual(titles(check), ["休憩", "プランク", "休憩", "サイドプランク右", "休憩",
                                       "サイドプランク左", "休憩", "ロシアンツイスト"])
        XCTAssertFalse(check.isAllowed)
        let manual = AutoProgressCheck(menu: AutoProgressCheck.manualStartVariant(of: longTimedMenu))
        XCTAssertTrue(manual.isAllowed)
        XCTAssertLessThanOrEqual(manual.longestChain.count, 3)
    }

    func testRoundBoundaryRestIsCounted() {
        // Last exercise timed, then the between-rounds rest, then a timed first exercise: one chain.
        let m = menu([timed("プランク", 30), timed("サイドプランク", 30)], rounds: 2, rest: 10, roundRest: 60)
        let plan = Plan(menu: m)
        XCTAssertEqual(plan.autoChain(from: 0).map { plan.steps[$0].title },
                       ["プランク", "休憩", "サイドプランク", "周回間休憩", "プランク", "休憩", "サイドプランク"])
        XCTAssertFalse(AutoProgressCheck(plan: plan).isAllowed)
    }

    func testChainStopsAtManualStart() {
        let plan = Plan(menu: menu([reps("腕立て伏せ", 10), timed("プランク", 30)], autoStart: false))
        XCTAssertEqual(plan.autoChain(from: 1).map { plan.steps[$0].title }, ["休憩", "プランク"])
    }
}

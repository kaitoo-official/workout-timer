import Foundation
@testable import WorkoutCore

let t0 = Date(timeIntervalSince1970: 1_800_000_000)

func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

func reps(_ name: String, _ n: Int, rest: Int? = nil) -> Exercise {
    Exercise(name: name, amount: .reps(n), restAfterOverride: rest)
}

func timed(_ name: String, _ s: Int, rest: Int? = nil) -> Exercise {
    Exercise(name: name, amount: .seconds(s), restAfterOverride: rest)
}

func menu(_ exercises: [Exercise], rounds: Int = 1, rest: Int = 20, roundRest: Int = 30,
          autoStart: Bool = true) -> Menu {
    Menu(name: "テスト", rounds: rounds, restBetweenExercises: rest, restBetweenRounds: roundRest,
         autoStartTimed: autoStart, exercises: exercises)
}

/// rest → plank → rest → push-ups, the shape verified on device in build 6.
let mixedMenu = menu([reps("腕立て伏せ", 10), timed("プランク", 20), reps("スクワット", 10)])

/// The "timed chain" from docs/動作ルール.md §6 (8 rows after the first exercise).
let longTimedMenu = menu([reps("レッグレイズ", 20), timed("プランク", 30), timed("サイドプランク右", 30),
                          timed("サイドプランク左", 30), reps("ロシアンツイスト", 30)])

import Foundation

/// The owner's three starter menus from docs/MVP仕様・画面設計.md (all 3 rounds).
/// Provisional and editable in the app: rest 60s / 90s are proposals, not approved values;
/// left/right splits marked 未確定 in the spec are kept as single exercises until confirmed;
/// インバーテッドロウ has no count in the spec and starts at 10.
public enum PersonalMenus {
    public static func all() -> [Menu] { [chest(), legsAndArms(), backAndAbs()] }

    static func reps(_ name: String, _ n: Int) -> Exercise { Exercise(name: name, amount: .reps(n)) }

    public static func chest() -> Menu {
        Menu(name: "CHEST", rounds: 3, restBetweenExercises: 60, restBetweenRounds: 90, autoStartTimed: false,
             exercises: [reps("ノーマル", 15), reps("デクライン", 15), reps("ナロー", 15)])
    }

    public static func legsAndArms() -> Menu {
        Menu(name: "LEGS & ARMS", rounds: 3, restBetweenExercises: 60, restBetweenRounds: 90, autoStartTimed: false,
             exercises: [
                reps("ダンベルスクワット", 15), reps("ダンベルカール", 15),
                reps("ブルガリアンスクワット右", 15), reps("ハンマーカール", 15),
                reps("ブルガリアンスクワット左", 15), reps("リバースカール", 15),
                reps("ダンベルカーフレイズ", 15), reps("バックリフト（左右）", 15),
             ])
    }

    public static func backAndAbs() -> Menu {
        Menu(name: "BACK & ABS", rounds: 3, restBetweenExercises: 60, restBetweenRounds: 90, autoStartTimed: false,
             exercises: [
                reps("RDL", 15), reps("バックエクステンション", 20),
                reps("Y", 15), reps("T", 15), reps("W", 15),
                reps("インバーテッドロウ", 10),
                reps("片腕ローイング右", 15), reps("片腕ローイング左", 15),
                reps("レッグレイズ", 20), reps("ロシアンツイスト", 30),
             ])
    }
}

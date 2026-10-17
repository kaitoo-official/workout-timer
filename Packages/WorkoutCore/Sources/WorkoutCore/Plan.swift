import Foundation

/// One segment of a workout: an exercise or a rest. Built from a Menu (docs/動作ルール.md §1–2).
public struct Step: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case exercise, rest, roundRest }

    public let index: Int
    public let kind: Kind
    /// 1-based round the step belongs to.
    public let round: Int
    /// For an exercise, its position in the menu. For a rest, the exercise that follows it.
    public let exerciseIndex: Int
    public let title: String
    public let reps: Int?
    public let seconds: Int?
    /// Timed exercise with auto start off: waits for a start action.
    public let startsManually: Bool

    public var isRest: Bool { kind != .exercise }
    /// Repetition exercises wait for a completion action; everything else ends on time.
    public var endsAutomatically: Bool { reps == nil }
    public var amountLabel: String {
        if let reps { return "\(reps)回" }
        return Amount.clock(seconds ?? 0)
    }
}

public struct Plan: Equatable, Sendable {
    public let steps: [Step]
    public let rounds: Int

    public init(menu: Menu) {
        var steps: [Step] = []
        let count = menu.exercises.count
        let rounds = max(1, menu.rounds)
        for round in 1...rounds {
            for (i, exercise) in menu.exercises.enumerated() {
                let isTimed: Bool
                var reps: Int?
                var seconds: Int?
                switch exercise.amount {
                case .reps(let n): reps = n; isTimed = false
                case .seconds(let s): seconds = s; isTimed = true
                }
                steps.append(Step(index: steps.count, kind: .exercise, round: round, exerciseIndex: i,
                                  title: exercise.name, reps: reps, seconds: seconds,
                                  startsManually: isTimed && !menu.autoStartTimed))
                let isLastInRound = i == count - 1
                if isLastInRound && round == rounds { break }
                let rest = isLastInRound ? menu.restBetweenRounds : (exercise.restAfterOverride ?? menu.restBetweenExercises)
                guard rest > 0 else { continue }
                steps.append(Step(index: steps.count, kind: isLastInRound ? .roundRest : .rest,
                                  round: round, exerciseIndex: isLastInRound ? 0 : i + 1,
                                  title: isLastInRound ? "周回間休憩" : "休憩", reps: nil, seconds: rest,
                                  startsManually: false))
            }
        }
        self.steps = steps
        self.rounds = rounds
    }

    /// The next exercise at or after `index` (what a rest leads to).
    public func nextExercise(after index: Int) -> Step? {
        steps.dropFirst(index + 1).first { $0.kind == .exercise }
    }
}

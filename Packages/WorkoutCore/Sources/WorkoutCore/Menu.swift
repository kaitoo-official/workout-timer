import Foundation

/// A user's workout menu. JSON format is specified in docs/メニュー形式.md.
public struct Menu: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var rounds: Int
    public var restBetweenExercises: Int
    public var restBetweenRounds: Int
    public var autoStartTimed: Bool
    public var exercises: [Exercise]

    public init(id: UUID = UUID(), name: String, rounds: Int, restBetweenExercises: Int,
                restBetweenRounds: Int, autoStartTimed: Bool, exercises: [Exercise]) {
        self.id = id
        self.name = name
        self.rounds = rounds
        self.restBetweenExercises = restBetweenExercises
        self.restBetweenRounds = restBetweenRounds
        self.autoStartTimed = autoStartTimed
        self.exercises = exercises
    }
}

public struct Exercise: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var amount: Amount
    /// Replaces the between-exercise rest after this exercise. Ignored after the last exercise
    /// of a round, where the between-rounds rest applies.
    public var restAfterOverride: Int?

    public init(id: UUID = UUID(), name: String, amount: Amount, restAfterOverride: Int? = nil) {
        self.id = id
        self.name = name
        self.amount = amount
        self.restAfterOverride = restAfterOverride
    }
}

/// Encoded as `{"type": "reps" | "seconds", "value": Int}` so other platforms can read it.
public enum Amount: Equatable, Sendable {
    case reps(Int)
    case seconds(Int)

    public var label: String {
        switch self {
        case .reps(let n): return "\(n)回"
        case .seconds(let s): return Amount.clock(s)
        }
    }

    static func clock(_ seconds: Int) -> String {
        seconds >= 60 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : "\(seconds)秒"
    }
}

extension Amount: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let value = try c.decode(Int.self, forKey: .value)
        switch try c.decode(String.self, forKey: .type) {
        case "reps": self = .reps(value)
        case "seconds": self = .seconds(value)
        case let other:
            throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown amount type \(other)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .reps(let n): try c.encode("reps", forKey: .type); try c.encode(n, forKey: .value)
        case .seconds(let s): try c.encode("seconds", forKey: .type); try c.encode(s, forKey: .value)
        }
    }
}

// MARK: - Validation

public enum MenuIssue: Equatable, Sendable {
    case emptyName
    case nameTooLong
    case roundsOutOfRange
    case restOutOfRange
    case noExercises
    case tooManyExercises
    case exerciseNameEmpty(index: Int)
    case exerciseNameTooLong(index: Int)
    case amountOutOfRange(index: Int)
    case overrideOutOfRange(index: Int)
}

public enum MenuLimits {
    public static let nameLength = 1...40
    public static let rounds = 1...20
    public static let rest = 0...1800
    public static let exercises = 1...50
    public static let reps = 1...999
    public static let seconds = 1...3600
}

extension Menu {
    public func validate() -> [MenuIssue] {
        var issues: [MenuIssue] = []
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { issues.append(.emptyName) }
        if trimmed.count > MenuLimits.nameLength.upperBound { issues.append(.nameTooLong) }
        if !MenuLimits.rounds.contains(rounds) { issues.append(.roundsOutOfRange) }
        if !MenuLimits.rest.contains(restBetweenExercises) || !MenuLimits.rest.contains(restBetweenRounds) {
            issues.append(.restOutOfRange)
        }
        if exercises.isEmpty { issues.append(.noExercises) }
        if exercises.count > MenuLimits.exercises.upperBound { issues.append(.tooManyExercises) }
        for (i, e) in exercises.enumerated() {
            let n = e.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if n.isEmpty { issues.append(.exerciseNameEmpty(index: i)) }
            if n.count > MenuLimits.nameLength.upperBound { issues.append(.exerciseNameTooLong(index: i)) }
            switch e.amount {
            case .reps(let r): if !MenuLimits.reps.contains(r) { issues.append(.amountOutOfRange(index: i)) }
            case .seconds(let s): if !MenuLimits.seconds.contains(s) { issues.append(.amountOutOfRange(index: i)) }
            }
            if let o = e.restAfterOverride, !MenuLimits.rest.contains(o) { issues.append(.overrideOutOfRange(index: i)) }
        }
        return issues
    }
}

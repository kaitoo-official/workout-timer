import Foundation

/// Minutes and seconds for the editor's two-column wheel. Menus keep storing whole seconds;
/// this only converts for display and input (docs/動作ルール.md §10).
public struct MinutesSeconds: Equatable, Sendable {
    public var minutes: Int
    public var seconds: Int

    public init(minutes: Int, seconds: Int) {
        self.minutes = minutes
        self.seconds = seconds
    }

    public init(totalSeconds: Int) {
        let total = max(0, totalSeconds)
        minutes = total / 60
        seconds = total % 60
    }

    public var totalSeconds: Int { minutes * 60 + seconds }
}

/// Which duration is being edited, with the limits from MenuLimits.
public enum DurationField: Sendable {
    /// Timed exercise: 1 second to 60 minutes (0 is not allowed).
    case exercise
    /// Rest between exercises / rounds / override: 0 to 30 minutes (0 = no rest step).
    case rest

    public var range: ClosedRange<Int> {
        switch self {
        case .exercise: return MenuLimits.seconds
        case .rest: return MenuLimits.rest
        }
    }

    public var minuteRange: ClosedRange<Int> { 0...(range.upperBound / 60) }

    /// Seconds the wheel offers for a minute value: 00–59, except at the top minute where only
    /// values up to the limit remain (60:00 for exercises, 30:00 for rests).
    public func secondRange(forMinutes minutes: Int) -> ClosedRange<Int> {
        let left = range.upperBound - minutes * 60
        return 0...max(0, min(59, left))
    }

    public func isValid(_ value: MinutesSeconds) -> Bool {
        value.minutes >= 0 && (0...59).contains(value.seconds) && range.contains(value.totalSeconds)
    }

    /// Keeps the seconds column inside `secondRange` after the minutes column moved.
    public func adjusted(_ value: MinutesSeconds) -> MinutesSeconds {
        var v = value
        v.minutes = min(max(v.minutes, minuteRange.lowerBound), minuteRange.upperBound)
        v.seconds = min(v.seconds, secondRange(forMinutes: v.minutes).upperBound)
        return v
    }
}

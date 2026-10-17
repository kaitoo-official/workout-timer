import Foundation

/// Limits derived from device run 2026-10-17 (iPhone 15 Pro, iOS 26.6.2). They are a safe fixed
/// value, not a guarantee from Apple; the app still handles scheduling failures at runtime.
public enum LiveActivityLimits {
    /// Rows the lock-screen "block" display can show, and steps scheduled ahead in the foreground
    /// (5 concurrent activities were accepted; one slot is kept free).
    public static let chainRows = 4
}

extension Plan {
    /// Steps that follow on their own once step `start` is running: from `start` up to and
    /// including the next step that needs the user (repetitions, or a manual-start timed
    /// exercise), or the end of the plan. Rests and between-rounds rests are counted.
    public func autoChain(from start: Int) -> [Int] {
        guard steps.indices.contains(start) else { return [] }
        var rows = [start]
        var current = start
        while steps[current].endsAutomatically, current + 1 < steps.count {
            let next = current + 1
            rows.append(next)
            if steps[next].startsManually || !steps[next].endsAutomatically { break }
            current = next
        }
        return rows
    }

    /// The longest automatic chain in the plan, over every possible starting step (a session can
    /// reach any step by skipping or resuming).
    public func longestAutoChain() -> [Int] {
        steps.indices.map { autoChain(from: $0) }.max { $0.count < $1.count } ?? []
    }
}

/// Pre-start check (docs/動作ルール.md §6).
public struct AutoProgressCheck: Equatable, Sendable {
    public let longestChain: [Step]
    public let limit: Int

    public var isAllowed: Bool { longestChain.count <= limit }

    public init(plan: Plan, limit: Int = LiveActivityLimits.chainRows) {
        self.longestChain = plan.longestAutoChain().map { plan.steps[$0] }
        self.limit = limit
    }

    public init(menu: Menu, limit: Int = LiveActivityLimits.chainRows) {
        self.init(plan: Plan(menu: menu), limit: limit)
    }

    /// The same menu with timed exercises waiting for a start action. Its chains are at most
    /// "timed → rest → next exercise", so it always passes the check.
    public static func manualStartVariant(of menu: Menu) -> Menu {
        var m = menu
        m.autoStartTimed = false
        return m
    }
}

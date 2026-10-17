import Foundation

/// A running workout. Pure value type: the app and the lock-screen intents both load it,
/// apply actions with the current time, and save it (docs/動作ルール.md §3–5, §9).
public struct Session: Codable, Equatable, Sendable {
    public static let schemaVersion = 1
    public static let undoDepth = 20

    public enum Phase: Codable, Equatable, Sendable {
        /// Timed exercise with auto start off.
        case waitingStart
        case running(startedAt: Date, endAt: Date)
        case paused(remaining: TimeInterval)
        /// Repetition exercise.
        case waitingCompletion(since: Date)
    }

    public enum Ending: String, Codable, Sendable { case completed, aborted }

    /// Phase without absolute times, so an undo can restart it relative to "now".
    enum RelativePhase: Codable, Equatable, Sendable {
        case waitingStart
        case running(elapsed: TimeInterval, remaining: TimeInterval)
        case paused(remaining: TimeInterval)
        case waitingCompletion
    }

    struct Snapshot: Codable, Equatable, Sendable {
        var stepIndex: Int
        var phase: RelativePhase
        var completedExercises: Int
        var skippedExercises: Int
    }

    public var schemaVersion = Session.schemaVersion
    public let id: UUID
    /// Copy of the menu at start, so editing the menu does not disturb a running session.
    public let menu: Menu
    public let startedAt: Date
    public private(set) var stepIndex: Int
    public private(set) var phase: Phase
    public private(set) var completedExercises = 0
    public private(set) var skippedExercises = 0
    public private(set) var ending: Ending?
    public private(set) var endedAt: Date?
    var undoStack: [Snapshot] = []

    public var plan: Plan { Plan(menu: menu) }
    public var isFinished: Bool { ending != nil }
    public var canUndo: Bool { !undoStack.isEmpty && !isFinished }

    public init(id: UUID = UUID(), menu: Menu, at now: Date) {
        self.id = id
        self.menu = menu
        self.startedAt = now
        self.stepIndex = 0
        self.phase = .waitingStart
        let plan = Plan(menu: menu)
        if plan.steps.isEmpty {
            ending = .completed
            endedAt = now
        } else {
            phase = Session.beginPhase(plan.steps[0], at: now)
        }
    }

    public var currentStep: Step? {
        let steps = plan.steps
        return isFinished || stepIndex >= steps.count ? nil : steps[stepIndex]
    }

    /// Remaining time of the current step at `now` (nil for steps waiting on the user).
    public func remaining(at now: Date) -> TimeInterval? {
        switch phase {
        case .running(_, let endAt): return max(0, endAt.timeIntervalSince(now))
        case .paused(let r): return r
        case .waitingStart: return currentStep?.seconds.map(TimeInterval.init)
        case .waitingCompletion: return nil
        }
    }

    // MARK: Time

    /// Moves past every step whose end time has passed. Each next step starts exactly at the
    /// previous end time, so delays do not accumulate. Returns true if anything changed.
    @discardableResult
    public mutating func advance(to now: Date) -> Bool {
        var changed = false
        while !isFinished, case .running(_, let endAt) = phase, endAt <= now {
            if let step = currentStep, step.kind == .exercise { completedExercises += 1 }
            moveToNext(at: endAt)
            changed = true
        }
        return changed
    }

    // MARK: Actions

    public enum Action: String, Codable, Sendable {
        case complete, start, pause, resume, extendRest, skip, next, undo, finish
    }

    /// Which step(s) the user was looking at when acting. Stale or repeated taps are ignored.
    public enum Target: Codable, Equatable, Sendable {
        case step(Int)
        case range(ClosedRange<Int>)
        case any

        func contains(_ index: Int) -> Bool {
            switch self {
            case .step(let i): return i == index
            case .range(let r): return r.contains(index)
            case .any: return true
            }
        }
    }

    public enum Rejection: Error, Equatable, Sendable {
        case finished
        case staleTarget
        case notAllowed
        case nothingToUndo
    }

    public static let defaultRestExtension: TimeInterval = 30

    /// Applies a user action at `now`. Always advances time first. Returns nil when applied.
    @discardableResult
    public mutating func apply(_ action: Action, target: Target = .any, at now: Date,
                               extendBy seconds: TimeInterval = Session.defaultRestExtension) -> Rejection? {
        advance(to: now)
        guard !isFinished else { return .finished }
        if action != .undo && action != .finish {
            guard target.contains(stepIndex) else { return .staleTarget }
        }
        guard let step = currentStep else { return .finished }

        switch action {
        case .complete:
            guard case .waitingCompletion = phase else { return .notAllowed }
            pushUndo(at: now)
            completedExercises += 1
            moveToNext(at: now)
        case .start:
            guard case .waitingStart = phase, let s = step.seconds else { return .notAllowed }
            pushUndo(at: now)
            phase = .running(startedAt: now, endAt: now.addingTimeInterval(TimeInterval(s)))
        case .pause:
            guard case .running(_, let endAt) = phase else { return .notAllowed }
            phase = .paused(remaining: max(0, endAt.timeIntervalSince(now)))
        case .resume:
            guard case .paused(let r) = phase else { return .notAllowed }
            phase = .running(startedAt: now, endAt: now.addingTimeInterval(r))
        case .extendRest:
            guard step.isRest else { return .notAllowed }
            switch phase {
            case .running(let startedAt, let endAt):
                pushUndo(at: now)
                phase = .running(startedAt: startedAt, endAt: endAt.addingTimeInterval(seconds))
            case .paused(let r):
                pushUndo(at: now)
                phase = .paused(remaining: r + seconds)
            default:
                return .notAllowed
            }
        case .skip:
            pushUndo(at: now)
            if step.kind == .exercise { skippedExercises += 1 }
            moveToNext(at: now)
        case .next:
            if case .waitingCompletion = phase {
                return apply(.complete, target: target, at: now)
            }
            return apply(.skip, target: target, at: now)
        case .undo:
            guard let snapshot = undoStack.popLast() else { return .nothingToUndo }
            restore(snapshot, at: now)
        case .finish:
            ending = .aborted
            endedAt = now
        }
        return nil
    }

    // MARK: Internals

    static func beginPhase(_ step: Step, at time: Date) -> Phase {
        if let s = step.seconds {
            return step.startsManually ? .waitingStart : .running(startedAt: time, endAt: time.addingTimeInterval(TimeInterval(s)))
        }
        return .waitingCompletion(since: time)
    }

    private mutating func moveToNext(at time: Date) {
        let steps = plan.steps
        stepIndex += 1
        if stepIndex >= steps.count {
            stepIndex = steps.count - 1
            ending = .completed
            endedAt = time
        } else {
            phase = Session.beginPhase(steps[stepIndex], at: time)
        }
    }

    private mutating func pushUndo(at now: Date) {
        let relative: RelativePhase
        switch phase {
        case .waitingStart: relative = .waitingStart
        case .running(let startedAt, let endAt):
            relative = .running(elapsed: max(0, now.timeIntervalSince(startedAt)), remaining: max(0, endAt.timeIntervalSince(now)))
        case .paused(let r): relative = .paused(remaining: r)
        case .waitingCompletion: relative = .waitingCompletion
        }
        undoStack.append(Snapshot(stepIndex: stepIndex, phase: relative,
                                  completedExercises: completedExercises, skippedExercises: skippedExercises))
        if undoStack.count > Session.undoDepth { undoStack.removeFirst(undoStack.count - Session.undoDepth) }
    }

    private mutating func restore(_ s: Snapshot, at now: Date) {
        stepIndex = s.stepIndex
        completedExercises = s.completedExercises
        skippedExercises = s.skippedExercises
        switch s.phase {
        case .waitingStart: phase = .waitingStart
        case .running(let elapsed, let remaining):
            phase = .running(startedAt: now.addingTimeInterval(-elapsed), endAt: now.addingTimeInterval(remaining))
        case .paused(let r): phase = .paused(remaining: r)
        case .waitingCompletion: phase = .waitingCompletion(since: now)
        }
    }
}

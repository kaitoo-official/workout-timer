import ActivityKit
import AppIntents
import Foundation

// Compiled into the app and the widget extension. The widget only renders this data; the
// intents run in the app process (LiveActivityIntent), where SessionController does the work.

struct WorkoutActivityAttributes: ActivityAttributes {
    struct Row: Codable, Hashable {
        var stepIndex: Int
        var title: String
        /// "15回" / "0:30"
        var detail: String
        var isRest: Bool
        /// Projected times. `end` is nil for a step that waits for the user.
        var start: Date?
        var end: Date?
        var waitsForStart: Bool
    }

    struct ContentState: Codable, Hashable {
        enum Kind: String, Codable { case single, block }
        var kind: Kind
        var rows: [Row]
        var round: Int
        var rounds: Int
        /// Single view: the step after this one (empty when none).
        var next: String
        var paused: Bool
        var pausedRemaining: Double?
        /// Step range this content covers; sent back with button taps to ignore stale taps.
        var firstStep: Int
        var lastStep: Int
    }

    var menuName: String
    var sessionID: String
}

enum WorkoutIntentAction: String {
    case next, toggle, start, extendRest
}

/// Runs the action in the app process. The widget copy of the intents never executes this
/// (LiveActivityIntent runs in the app; verified on device with the probe).
func runWorkoutIntent(_ action: WorkoutIntentAction, first: Int, last: Int) async {
    #if !WIDGET_EXTENSION
    await SessionController.shared.handleIntent(action, first: first, last: last)
    #endif
}

struct NextStepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "完了・次へ"
    @Parameter(title: "first") var first: Int
    @Parameter(title: "last") var last: Int
    init() {}
    init(first: Int, last: Int) { self.first = first; self.last = last }
    func perform() async throws -> some IntentResult {
        await runWorkoutIntent(.next, first: first, last: last)
        return .result()
    }
}

struct TogglePauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "一時停止・再開"
    @Parameter(title: "first") var first: Int
    @Parameter(title: "last") var last: Int
    init() {}
    init(first: Int, last: Int) { self.first = first; self.last = last }
    func perform() async throws -> some IntentResult {
        await runWorkoutIntent(.toggle, first: first, last: last)
        return .result()
    }
}

struct StartStepIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "開始"
    @Parameter(title: "first") var first: Int
    @Parameter(title: "last") var last: Int
    init() {}
    init(first: Int, last: Int) { self.first = first; self.last = last }
    func perform() async throws -> some IntentResult {
        await runWorkoutIntent(.start, first: first, last: last)
        return .result()
    }
}

struct ExtendRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "休憩を30秒延長"
    @Parameter(title: "first") var first: Int
    @Parameter(title: "last") var last: Int
    init() {}
    init(first: Int, last: Int) { self.first = first; self.last = last }
    func perform() async throws -> some IntentResult {
        await runWorkoutIntent(.extendRest, first: first, last: last)
        return .result()
    }
}

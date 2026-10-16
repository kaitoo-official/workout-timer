import ActivityKit
import AppIntents
import Foundation

// Compiled into both the app and the widget extension.
// The engine (notifications, Activity.request/update/end, storage) lives in the app target only.

struct ProbeAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var title: String
        var detail: String          // "20秒" or "15回"
        var start: Date
        var end: Date
        var paused: Bool
        var remaining: Double
        var repetitions: Bool
        var step: Int               // 1-based position in the plan
        var stepCount: Int
        // Look-ahead for the step after this one. Used by the widget once the content goes stale,
        // so it can show the next step without the app running (one switch per update at most).
        var nextTitle: String
        var nextDetail: String
        var nextStart: Date?
        var nextEnd: Date?
        var nextRepetitions: Bool
    }
    var name: String
    var mode: String                // ProbeMode.rawValue
}

struct ProbeStep: Hashable {
    let title: String
    let seconds: Double?            // nil = repetition step, waits for the user
    let reps: Int?
    let rest: Bool

    static func timed(_ title: String, _ seconds: Double, rest: Bool = false) -> Self {
        .init(title: title, seconds: seconds, reps: nil, rest: rest)
    }
    static func repetitions(_ title: String, _ count: Int) -> Self {
        .init(title: title, seconds: nil, reps: count, rest: false)
    }
    var detail: String {
        if let reps { return "\(reps)回" }
        return "\(Int(seconds ?? 0))秒"
    }
}

enum ProbePlan {
    // Seven timed steps in a row (incl. a rest between left and right), then a repetition step.
    // 20-second steps leave room for the 5-second countdown before each boundary.
    static let steps: [ProbeStep] = [
        .timed("休憩", 20, rest: true),
        .timed("プランク", 20),
        .timed("休憩", 20, rest: true),
        .timed("サイドプランク右", 20),
        .timed("左右の間の休憩", 20, rest: true),
        .timed("サイドプランク左", 20),
        .timed("休憩", 20, rest: true),
        .repetitions("腕立て伏せ", 15),
    ]
}

enum ProbeMode: String, Codable, CaseIterable, Identifiable {
    case single         // one Live Activity, updated by the app, stale-date look-ahead
    case scheduled      // iOS 26: one Live Activity per step, scheduled to start at each boundary
    var id: String { rawValue }
    var label: String {
        switch self {
        case .single: return "A: 1つのLA＋先読み"
        case .scheduled: return "B: 区間ごと予約LA"
        }
    }
}

// LiveActivityIntent runs perform() in the app process (the system launches the app in the
// background if needed), so the widget copy never executes the engine.
struct ToggleProbeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "一時停止・再開"
    init() {}
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await ProbeEngine.action(.toggle, source: "LA")
        #endif
        return .result()
    }
}

struct NextProbeIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "スキップ・完了"
    init() {}
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await ProbeEngine.action(.next, source: "LA")
        #endif
        return .result()
    }
}

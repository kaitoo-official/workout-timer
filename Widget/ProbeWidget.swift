import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// What the widget can show without the app: the step in the content state, or — once the
/// content is stale — the look-ahead step. Mode B's stale activities are finished steps.
private struct Shown {
    let title: String
    let detail: String
    let interval: ClosedRange<Date>?    // nil = no running timer (paused / repetitions)
    let repetitions: Bool
    let paused: Bool
    let remaining: Double
    let lookAhead: Bool
    let finished: Bool
    let next: String

    init(_ state: ProbeAttributes.ContentState, stale: Bool, mode: String) {
        if stale && mode == ProbeMode.scheduled.rawValue {
            title = state.title; detail = "終了"; interval = nil; repetitions = false
            paused = false; remaining = 0; lookAhead = false; finished = true; next = state.nextTitle
        } else if stale, let start = state.nextStart, let end = state.nextEnd {
            title = state.nextTitle; detail = state.nextDetail
            repetitions = state.nextRepetitions
            interval = repetitions ? nil : start...max(start, end)
            paused = false; remaining = 0; lookAhead = true; finished = false; next = "（アプリ更新待ち）"
        } else {
            title = state.title; detail = state.detail
            repetitions = state.repetitions; paused = state.paused; remaining = state.remaining
            interval = (repetitions || paused) ? nil : state.start...state.end
            lookAhead = false; finished = false; next = state.nextTitle
        }
    }
}

private struct TimeLabel: View {
    let shown: Shown
    var body: some View {
        if shown.finished { Text("終了") }
        else if shown.repetitions { Text(shown.detail) }
        else if shown.paused { Text("停止 \(Int(ceil(shown.remaining)))秒") }
        else if let interval = shown.interval { Text(timerInterval: interval, countsDown: true).monospacedDigit() }
        else { Text("--") }
    }
}

private struct Controls: View {
    let shown: Shown
    var body: some View {
        HStack {
            if !shown.repetitions {
                Button(intent: ToggleProbeIntent()) { Text(shown.paused ? "再開" : "一時停止") }
            }
            Button(intent: NextProbeIntent()) { Text(shown.repetitions ? "完了" : "スキップ") }
        }
        .buttonStyle(.bordered)
        .tint(.orange)
    }
}

private struct ProbeDisplay: View {
    let state: ProbeAttributes.ContentState
    let shown: Shown
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(state.step)/\(state.stepCount)  \(shown.title)").font(.headline)
                Spacer()
                TimeLabel(shown: shown).font(.title2.bold()).frame(maxWidth: 110, alignment: .trailing)
            }
            Text("次：\(shown.next)").font(.caption)
            if shown.lookAhead { Text("先読み表示（アプリ未実行）").font(.caption2).foregroundStyle(.yellow) }
            if !shown.finished { Controls(shown: shown) }
        }
    }
}

@main
struct ProbeWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProbeAttributes.self) { context in
            let shown = Shown(context.state, stale: context.isStale, mode: context.attributes.mode)
            VStack(alignment: .leading, spacing: 4) {
                Text("筋トレ検証 \(context.attributes.name)").font(.caption).foregroundStyle(.secondary)
                ProbeDisplay(state: context.state, shown: shown)
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            let shown = Shown(context.state, stale: context.isStale, mode: context.attributes.mode)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    ProbeDisplay(state: context.state, shown: shown)
                }
            } compactLeading: {
                Image(systemName: shown.title.contains("休憩") ? "pause.circle" : "figure.strengthtraining.traditional")
            } compactTrailing: {
                TimeLabel(shown: shown).frame(maxWidth: 52)
            } minimal: {
                TimeLabel(shown: shown).frame(maxWidth: 40)
            }
            .keylineTint(.orange)
        }
    }
}

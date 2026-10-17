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
    let step: Int

    init(_ state: ProbeAttributes.ContentState, stale: Bool, mode: String) {
        if stale && mode == ProbeMode.scheduled.rawValue {
            title = state.title; detail = "終了"; interval = nil; repetitions = false
            paused = false; remaining = 0; lookAhead = false; finished = true; next = state.nextTitle
            step = state.step
        } else if stale, let start = state.nextStart, let end = state.nextEnd {
            title = state.nextTitle; detail = state.nextDetail
            repetitions = state.nextRepetitions
            interval = repetitions ? nil : start...max(start, end)
            paused = false; remaining = 0; lookAhead = true; finished = false; next = "（アプリ更新待ち）"
            step = state.step + 1
        } else {
            title = state.title; detail = state.detail
            repetitions = state.repetitions; paused = state.paused; remaining = state.remaining
            interval = (repetitions || paused) ? nil : state.start...state.end
            lookAhead = false; finished = false; next = state.nextTitle
            step = state.step
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
                Text("\(shown.step)/\(state.stepCount)  \(shown.title)").font(.headline)
                Spacer()
                TimeLabel(shown: shown).font(.title2.bold()).frame(maxWidth: 110, alignment: .trailing)
            }
            Text("次：\(shown.next)").font(.caption)
            if shown.lookAhead { Text("先読み表示（アプリ未実行）").font(.caption2).foregroundStyle(.yellow) }
            if !shown.finished { Controls(shown: shown) }
        }
    }
}

/// Mode C: no updates needed. Each row's timer and bar run on their own schedule, so the row
/// that is counting down is the current step even while the app is not running.
private struct TimelineDisplay: View {
    let state: ProbeAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(state.timeline.enumerated()), id: \.offset) { k, row in
                HStack(spacing: 6) {
                    Text("\(state.step + k)").font(.caption2).foregroundStyle(.secondary).frame(width: 14)
                    Text(row.title).font(.subheadline.bold()).lineLimit(1)
                    Spacer(minLength: 4)
                    if row.repetitions {
                        Text(row.detail).font(.subheadline)
                    } else {
                        ProgressView(timerInterval: row.start...row.end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                            .tint(.orange).frame(width: 60)
                        // A timer whose interval starts in the future stays frozen on device, so every
                        // row counts down to its own end from the first row's start (already passed).
                        // The current step's row therefore shows its true remaining time.
                        Text(timerInterval: state.timeline[0].start...row.end, countsDown: true)
                            .monospacedDigit().font(.subheadline).frame(width: 48, alignment: .trailing)
                    }
                }
            }
            HStack {
                Button(intent: ToggleProbeIntent()) { Text("一時停止") }
                Button(intent: NextProbeIntent()) { Text(state.repetitions ? "完了" : "スキップ") }
            }
            .buttonStyle(.bordered).tint(.orange).font(.caption)
        }
    }
}

private extension ProbeAttributes.ContentState {
    var usesTimeline: Bool { !timeline.isEmpty && !paused }
}

@main
struct ProbeWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProbeAttributes.self) { context in
            let shown = Shown(context.state, stale: context.isStale, mode: context.attributes.mode)
            VStack(alignment: .leading, spacing: 4) {
                Text("筋トレ検証 \(context.attributes.name)").font(.caption).foregroundStyle(.secondary)
                if context.state.usesTimeline {
                    TimelineDisplay(state: context.state)
                } else {
                    ProbeDisplay(state: context.state, shown: shown)
                }
            }
            .padding()
            .activityBackgroundTint(.black)
            .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            let shown = Shown(context.state, stale: context.isStale, mode: context.attributes.mode)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.usesTimeline {
                        TimelineDisplay(state: context.state)
                    } else {
                        ProbeDisplay(state: context.state, shown: shown)
                    }
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

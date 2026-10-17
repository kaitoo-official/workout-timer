import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

typealias WorkoutState = WorkoutActivityAttributes.ContentState
typealias WorkoutRow = WorkoutActivityAttributes.Row

/// One step: name, timer or amount, next step and the matching buttons.
struct SingleStepView: View {
    let state: WorkoutState
    let menuName: String

    var row: WorkoutRow? { state.rows.first }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(menuName).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(state.round)/\(state.rounds)周目").font(.caption).foregroundStyle(.secondary)
            }
            if let row {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.title).font(.title3.bold()).lineLimit(1)
                    Spacer()
                    StepTimeLabel(row: row, state: state).font(.title2.bold())
                }
                if !state.next.isEmpty {
                    Text("次：\(state.next)").font(.caption).lineLimit(1)
                }
                StepButtons(row: row, state: state)
            }
        }
    }
}

struct StepTimeLabel: View {
    let row: WorkoutRow
    let state: WorkoutState

    var body: some View {
        if state.paused, let remaining = state.pausedRemaining {
            Text("停止 \(Int(remaining.rounded(.up)) / 60):\(String(format: "%02d", Int(remaining.rounded(.up)) % 60))")
                .monospacedDigit()
        } else if let start = row.start, let end = row.end {
            Text(timerInterval: start...max(start, end), countsDown: true)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90, alignment: .trailing)
        } else {
            Text(row.waitsForStart ? "\(row.detail)・開始待ち" : row.detail)
        }
    }
}

struct StepButtons: View {
    let row: WorkoutRow
    let state: WorkoutState

    var body: some View {
        let first = state.firstStep, last = state.lastStep
        HStack {
            if state.paused || row.end != nil {
                // Timed exercise or rest: running or paused.
                Button(intent: TogglePauseIntent(first: first, last: last)) { Text(state.paused ? "再開" : "一時停止") }
                if row.isRest {
                    Button(intent: ExtendRestIntent(first: first, last: last)) { Text("+30秒") }
                }
                Button(intent: NextStepIntent(first: first, last: last)) { Text("スキップ") }
            } else if row.waitsForStart {
                Button(intent: StartStepIntent(first: first, last: last)) { Text("開始") }
                Button(intent: NextStepIntent(first: first, last: last)) { Text("スキップ") }
            } else {
                // Repetitions: never completes on its own.
                Button(intent: NextStepIntent(first: first, last: last)) { Text("完了") }
            }
        }
        .buttonStyle(.bordered)
        .tint(.orange)
        .font(.caption.bold())
    }
}

/// After a lock-screen action the following steps cannot be scheduled, so they are listed here.
/// Each bar runs on its own schedule; the row whose bar is shrinking is the current step.
/// The header never names a step, because it would go stale without an update.
struct BlockView: View {
    let state: WorkoutState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("進行予定").font(.caption.bold())
                Spacer()
                Text("\(state.round)/\(state.rounds)周目").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(state.rows, id: \.stepIndex) { row in
                HStack(spacing: 6) {
                    Text(row.title).font(.subheadline.bold()).lineLimit(1)
                    Spacer(minLength: 4)
                    if let start = row.start, let end = row.end, let origin = state.rows.first?.start {
                        ProgressView(timerInterval: start...max(start, end), countsDown: true) {
                            EmptyView()
                        } currentValueLabel: {
                            EmptyView()
                        }
                        .tint(row.isRest ? .teal : .orange)
                        .frame(width: 64)
                        // A timer whose interval starts in the future stays frozen on device, so every
                        // row counts to its own end from the first row's start (already passed).
                        Text(timerInterval: origin...max(origin, end), countsDown: true)
                            .monospacedDigit().font(.subheadline)
                            .frame(width: 48, alignment: .trailing)
                    } else {
                        Text(row.waitsForStart ? "\(row.detail)・開始待ち" : row.detail).font(.subheadline)
                    }
                }
            }
            HStack {
                Button(intent: TogglePauseIntent(first: state.firstStep, last: state.lastStep)) { Text("一時停止") }
                Button(intent: NextStepIntent(first: state.firstStep, last: state.lastStep)) { Text("完了・次へ") }
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .font(.caption.bold())
        }
    }
}

struct ActivityBody: View {
    let state: WorkoutState
    let menuName: String
    var body: some View {
        if state.kind == .block {
            BlockView(state: state)
        } else {
            SingleStepView(state: state, menuName: menuName)
        }
    }
}

struct CompactTrailing: View {
    let state: WorkoutState
    var body: some View {
        if state.kind == .block {
            Image(systemName: "list.bullet")
        } else if let row = state.rows.first {
            if state.paused {
                Text("停止")
            } else if let start = row.start, let end = row.end {
                Text(timerInterval: start...max(start, end), countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } else {
                Text(row.detail).monospacedDigit()
            }
        }
    }
}

@main
struct WorkoutActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            ActivityBody(state: context.state, menuName: context.attributes.menuName)
                .padding()
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    ActivityBody(state: context.state, menuName: context.attributes.menuName)
                }
            } compactLeading: {
                Image(systemName: context.state.rows.first?.isRest == true && context.state.kind == .single
                      ? "cup.and.saucer.fill" : "figure.strengthtraining.traditional")
                    .foregroundStyle(.orange)
            } compactTrailing: {
                CompactTrailing(state: context.state)
            } minimal: {
                CompactTrailing(state: context.state)
            }
            .keylineTint(.orange)
        }
    }
}

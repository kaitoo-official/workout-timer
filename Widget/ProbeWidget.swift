import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct ProbeDisplay: View {
    let state: ProbeAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.title).font(.headline)
            if state.repetitions { Text("15回・完了を押す") }
            else if state.paused { Text("停止中 \(Int(ceil(state.remaining)))秒") }
            else { Text(timerInterval: state.start...state.end, countsDown: true).monospacedDigit() }
            Text("次：\(state.next)").font(.caption)
            HStack {
                if !state.repetitions {
                    Button(intent: ToggleProbeIntent()) { Text(state.paused ? "再開" : "一時停止") }
                }
                Button(intent: NextProbeIntent()) { Text(state.repetitions ? "完了" : "スキップ") }
            }.buttonStyle(.bordered)
        }
    }
}

@main
struct ProbeWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProbeAttributes.self) { context in
            VStack(alignment: .leading) {
                Text("筋トレ・検証版").font(.caption)
                ProbeDisplay(state: context.state)
                if context.isStale { Text("区間終了・表示更新待ち").font(.caption).foregroundStyle(.orange) }
            }.padding().activityBackgroundTint(.black).activitySystemActionForegroundColor(.orange)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) { ProbeDisplay(state: context.state) }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.isStale { Text("区間終了・表示更新待ち").font(.caption) }
                }
            } compactLeading: {
                Image(systemName: context.state.title == "休憩" ? "pause.circle" : "figure.strengthtraining.traditional")
            } compactTrailing: {
                if context.state.repetitions { Text("15回") }
                else if context.state.paused { Text("停止") }
                else { Text(timerInterval: context.state.start...context.state.end, countsDown: true).monospacedDigit().frame(width: 48) }
            } minimal: {
                Image(systemName: "timer")
            }
            .keylineTint(.orange)
        }
    }
}

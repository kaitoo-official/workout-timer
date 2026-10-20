import SwiftUI
import WorkoutCore

/// The tappable value in a form row ("15回", "1分30秒"). Opens a wheel sheet.
struct ValueButton: View {
    let text: String
    let accessibilityTitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.body.monospacedDigit())
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(accessibilityTitle)：\(text)")
        .accessibilityHint("タップして変更")
    }
}

/// Label + value button in one form row.
struct WheelValueRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            ValueButton(text: value, accessibilityTitle: title, action: action)
        }
    }
}

enum DurationLabel {
    static func text(_ seconds: Int, field: DurationField) -> String {
        if field == .rest && seconds == 0 { return "なし" }
        return Format.duration(seconds)
    }
}

/// Edits a draft; only "決定" writes back. Swiping the sheet down or "キャンセル" keeps the
/// original value.
private struct WheelSheet<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let canCommit: Bool
    let onCommit: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("決定") { onCommit(); dismiss() }.disabled(!canCommit)
                    }
                }
        }
        .presentationDetents([.height(320)])
        .presentationDragIndicator(.visible)
    }
}

/// One-column wheel for repetitions (1回 steps, MenuLimits.reps).
struct RepsPickerSheet: View {
    let title: String
    let onCommit: (Int) -> Void
    @State private var draft: Int

    init(title: String, initial: Int, onCommit: @escaping (Int) -> Void) {
        self.title = title
        self.onCommit = onCommit
        _draft = State(initialValue: min(max(initial, MenuLimits.reps.lowerBound), MenuLimits.reps.upperBound))
    }

    var body: some View {
        WheelSheet(title: title, canCommit: true, onCommit: { onCommit(draft) }) {
            Picker(title, selection: $draft) {
                ForEach(MenuLimits.reps, id: \.self) { n in
                    Text("\(n)回").tag(n)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
        }
    }
}

/// Two independent wheels: minutes and seconds (00–59, two digits).
struct DurationPickerSheet: View {
    let title: String
    let field: DurationField
    let onCommit: (Int) -> Void
    @State private var minutes: Int
    @State private var seconds: Int

    init(title: String, field: DurationField, initial: Int, onCommit: @escaping (Int) -> Void) {
        self.title = title
        self.field = field
        self.onCommit = onCommit
        let start = field.adjusted(MinutesSeconds(totalSeconds: initial))
        _minutes = State(initialValue: start.minutes)
        _seconds = State(initialValue: start.seconds)
    }

    private var value: MinutesSeconds { MinutesSeconds(minutes: minutes, seconds: seconds) }

    var body: some View {
        WheelSheet(title: title, canCommit: field.isValid(value), onCommit: { onCommit(value.totalSeconds) }) {
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    Picker("分", selection: $minutes) {
                        ForEach(field.minuteRange, id: \.self) { m in
                            Text("\(m)分").tag(m)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .accessibilityLabel("分")
                    Picker("秒", selection: $seconds) {
                        ForEach(field.secondRange(forMinutes: minutes), id: \.self) { s in
                            Text(String(format: "%02d秒", s)).tag(s)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .accessibilityLabel("秒")
                    .id(minutes == field.minuteRange.upperBound)   // rebuild when the seconds list shrinks
                }
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(field.isValid(value) ? Color.secondary : Color.red)
            }
            .onChange(of: minutes) { _, _ in
                let fixed = field.adjusted(value)
                if fixed.seconds != seconds { seconds = fixed.seconds }
            }
        }
    }

    private var hint: String {
        if !field.isValid(value) { return "1秒以上にしてください" }
        if field == .rest && value.totalSeconds == 0 { return "休憩をはさみません" }
        return DurationLabel.text(value.totalSeconds, field: field)
    }
}

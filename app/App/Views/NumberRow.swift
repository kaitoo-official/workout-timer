import SwiftUI
import UIKit

/// A number that can be typed with the number pad or nudged with − / +.
/// Out-of-range input is clamped; leaving the field shows the stored value again.
struct NumberRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step = 1
    let unit: String

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 4)
            TextField("", text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(minWidth: 44, maxWidth: 72)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 6))
                .focused($focused)
                .accessibilityLabel("\(title)（\(unit)）")
            Text(unit).foregroundStyle(.secondary)
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
                .accessibilityLabel("\(title)を増減")
        }
        .onAppear { text = String(value) }
        .onChange(of: text) { _, new in
            let digits = String(new.filter(\.isNumber).prefix(5))
            if digits != new { text = digits; return }
            if let typed = Int(digits) { value = min(max(typed, range.lowerBound), range.upperBound) }
        }
        .onChange(of: value) { _, v in
            if !focused { text = String(v) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { text = String(value) }
        }
    }
}

extension View {
    /// "閉じる" above the number pad, which has no return key.
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("閉じる") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
}

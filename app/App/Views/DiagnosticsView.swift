import SwiftUI
import UIKit

/// Test aid: what the app scheduled and cleaned up, newest first. Copy and paste it into chat.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var lines = DiagnosticsLog.lines

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("ログをコピー") { UIPasteboard.general.string = DiagnosticsLog.lines.joined(separator: "\n") }
                    Button("ログを消去", role: .destructive) { DiagnosticsLog.clear(); lines = [] }
                }
                Section("新しい順") {
                    ForEach(Array(lines.reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .navigationTitle("動作記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
    }
}

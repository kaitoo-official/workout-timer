import SwiftUI
import Combine
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct WorkoutProbeApp: App {
    private let delegate = NotificationDelegate()
    init() { UNUserNotificationCenter.current().delegate = delegate }
    var body: some Scene { WindowGroup { ProbeView() } }
}

struct ProbeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = ProbeSession.load()
    @State private var message = "未検証：通知が届くことと、上部表示が自動で切り替わることは別です。"
    @State private var busy = false
    private let ticks = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("休憩10秒 → プランク10秒 → 休憩10秒 → 腕立て15回")
                    .font(.headline)
                if let session {
                    Text(session.content.title).font(.largeTitle.bold())
                    if session.phase == 3 { Text("15回・完了操作待ち") }
                    else if session.paused { Text("停止中 \(Int(ceil(session.remaining)))秒") }
                    else { Text(session.content.end, style: .timer).font(.system(size: 64, design: .rounded)).monospacedDigit() }
                    Text("次：\(session.content.next)")
                    if session.phase < 3 {
                        Button(session.paused ? "再開" : "一時停止") { run { try await ProbeEngine.action("toggle") } }
                    }
                    Button(session.phase == 3 ? "完了して終了" : "スキップ") { run { try await ProbeEngine.action("next") } }
                    Button("検証を終了", role: .destructive) { run { await ProbeEngine.stop() } }
                } else {
                    Button("通知許可を確認して検証開始") {
                        run {
                            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                            try await ProbeEngine.start()
                            message = allowed ? "開始しました。YouTubeまたはロック画面へ切り替えてください。" : "通知は不許可です。通知設定を確認してください。"
                        }
                    }
                }
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Text("この版はOSの動作確認専用です。5秒音声・メニュー編集・運動記録はまだ含みません。")
                    .font(.footnote)
            }
            .padding().buttonStyle(.borderedProminent).disabled(busy)
            .navigationTitle("筋トレ検証")
        }
        .preferredColorScheme(.dark)
        .onReceive(ticks) { _ in
            guard scenePhase == .active && !busy else { return }
            session = ProbeSession.load()
            if var current = session {
                let old = current.phase
                current.reconcile()
                if old != current.phase { run { try await ProbeEngine.publish(current) } }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { session = ProbeSession.load() }
        }
    }
    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        Task { @MainActor in
            defer { busy = false; session = ProbeSession.load() }
            do { try await work() } catch { message = error.localizedDescription }
        }
    }
}

import ActivityKit
import SwiftUI
import Combine
import UIKit
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    // Only called while the app is in the foreground; delivery never launches the app.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    // Records every process launch, including background launches (e.g. by a Live Activity
    // button), and whether the system starts the app when a scheduled Live Activity begins.
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        let state: String
        switch application.applicationState {
        case .active: state = "前面"
        case .inactive: state = "準備中"
        case .background: state = "バックグラウンド"
        @unknown default: state = "不明"
        }
        ProbeLog.add("アプリ起動（\(state)）")
        ActivityObserver.start()
        return true
    }
}

/// Logs Live Activity state changes while the process is alive.
enum ActivityObserver {
    private static var started = false
    static func start() {
        guard !started else { return }
        started = true
        Task {
            for activity in Activity<ProbeAttributes>.activities { watch(activity) }
            for await activity in Activity<ProbeAttributes>.activityUpdates {
                ProbeLog.add("LA追加 \(activity.attributes.name)=\(activity.activityState)")
                watch(activity)
            }
        }
    }
    private static func watch(_ activity: Activity<ProbeAttributes>) {
        Task {
            for await state in activity.activityStateUpdates {
                let background = await MainActor.run { UIApplication.shared.applicationState == .background }
                ProbeLog.add("LA状態 \(activity.attributes.name)→\(state)\(background ? "（裏）" : "")")
                guard state == .active, activity.attributes.mode == ProbeMode.scheduled.rawValue else { continue }
                // Ask for a little extra time so the refresh can finish if the system woke us for this.
                let task = await MainActor.run { UIApplication.shared.beginBackgroundTask(withName: "probe-refresh") }
                await ProbeEngine.refreshScheduled(trigger: "\(activity.attributes.name)開始\(background ? "・裏" : "")")
                await MainActor.run { UIApplication.shared.endBackgroundTask(task) }
            }
        }
    }
}

@main
struct WorkoutProbeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let delegate = NotificationDelegate()
    init() { UNUserNotificationCenter.current().delegate = delegate }
    var body: some Scene { WindowGroup { ProbeView() } }
}

struct ProbeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = ProbeSession.load()
    @State private var mode: ProbeMode = .scheduled
    @State private var plan: ProbePlan = .mixed
    @State private var log = ProbeLog.lines
    @State private var message = "通知が届くことと、上部・ロック画面の表示が自動で切り替わることは別に判定します。"
    @State private var busy = false
    private let ticks = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            List {
                Section("予定（\(session?.plan.label ?? plan.label)）") {
                    Text((session?.steps ?? plan.steps).map { "\($0.title)\($0.detail)" }.joined(separator: " → "))
                        .font(.footnote)
                }
                if let session {
                    Section("進行中 \(session.mode.label)") {
                        Text("\(session.index + 1)/\(session.steps.count)  \(session.step.title)")
                            .font(.title.bold())
                        if session.step.seconds == nil {
                            Text("\(session.step.detail)・完了操作待ち").font(.title2)
                        } else if session.paused {
                            Text("停止中 \(Int(ceil(session.remaining)))秒").font(.title2)
                        } else {
                            Text(timerInterval: session.start...max(session.start, session.end), countsDown: true)
                                .font(.system(size: 56, design: .rounded)).monospacedDigit()
                        }
                        HStack {
                            if session.step.seconds != nil {
                                Button(session.paused ? "再開" : "一時停止") { run { await ProbeEngine.action(.toggle, source: "アプリ") } }
                            }
                            Button(session.step.seconds == nil ? "完了" : "スキップ") { run { await ProbeEngine.action(.next, source: "アプリ") } }
                        }
                        Button("検証を終了", role: .destructive) { run { await ProbeEngine.stop(reason: "アプリ操作: 途中終了") } }
                    }
                } else {
                    Section("開始") {
                        Picker("方式", selection: $mode) {
                            ForEach(ProbeMode.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Picker("予定", selection: $plan) {
                            ForEach(ProbePlan.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Button("通知許可を確認して検証開始") {
                            run {
                                let allowed = try await UNUserNotificationCenter.current()
                                    .requestAuthorization(options: [.alert, .sound])
                                try await ProbeEngine.start(mode: mode, plan: plan)
                                message = allowed ? "開始しました。すぐYouTubeかロック画面へ切り替えてください。" : "通知は不許可です。設定を確認してください。"
                            }
                        }
                    }
                }
                Section {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Section("ログ（新しい順）") {
                    Button("ログをコピー") { UIPasteboard.general.string = ProbeLog.lines.joined(separator: "\n") }
                    Button("ログを消去") { ProbeLog.clear(); log = [] }
                    ForEach(Array(log.reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.caption.monospaced())
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy)
            .navigationTitle("筋トレ検証")
        }
        .preferredColorScheme(.dark)
        .onReceive(ticks) { _ in
            guard scenePhase == .active, !busy else { return }
            guard var current = ProbeSession.load() else { session = nil; return }
            if current.reconcile() {
                let advanced = current
                run { try await ProbeEngine.publish(advanced, reason: "前面で区間更新") }
            } else {
                session = current
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Recorded BEFORE the app reconciles, so the log shows what the system displayed
                // on its own. A correct screen after this point does not count as automatic switching.
                run { await ProbeLog.snapshot("アプリ復帰時") }
            case .background:
                ProbeLog.add("バックグラウンドへ")
            default:
                break
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        Task { @MainActor in
            defer {
                busy = false
                session = ProbeSession.load()
                log = ProbeLog.lines
            }
            do { try await work() } catch { message = error.localizedDescription }
        }
    }
}

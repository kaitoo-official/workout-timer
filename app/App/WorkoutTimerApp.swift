import SwiftUI
import UserNotifications
import WorkoutCore

/// SwiftUI also has a `Menu` view; the app refers to the workout menu by this name.
typealias WorkoutMenu = WorkoutCore.Menu

@main
struct WorkoutTimerApp: App {
    private let notificationDelegate = ForegroundNotificationDelegate()

    init() {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        _ = SessionController.shared
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    @State private var controller = SessionController.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let session = controller.session {
                if session.isFinished {
                    FinishView(session: session)
                } else {
                    TrainingView()
                }
            } else {
                MenuListView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await controller.resumeFromBackground() } }
        }
        .alert("お知らせ", isPresented: Binding(get: { controller.message != nil },
                                              set: { if !$0 { controller.message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(controller.message ?? "")
        }
    }
}

enum Format {
    /// 0:45 / 1:30 for timers.
    static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.up)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "45秒" / "1分30秒" for settings.
    static func duration(_ seconds: Int) -> String {
        if seconds < 60 { return "\(seconds)秒" }
        return seconds % 60 == 0 ? "\(seconds / 60)分" : "\(seconds / 60)分\(seconds % 60)秒"
    }
}

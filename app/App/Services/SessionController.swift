import ActivityKit
import Foundation
import Observation
import UIKit
import WorkoutCore

/// Single owner of menus, settings and the running session. The app screens and the lock-screen
/// intents both go through `perform`, so they share one progression path (docs/動作ルール.md).
@MainActor
@Observable
final class SessionController {
    static let shared = SessionController()

    private(set) var menus: [Menu] = []
    private(set) var session: Session?
    private(set) var settings = SoundSettings()
    /// Shown to the user when saving or loading failed. Never hides the failure.
    var message: String?

    @ObservationIgnored private let store: FileStore?
    @ObservationIgnored private let notifications = NotificationService()
    @ObservationIgnored private let activities = LiveActivityService()
    /// A menus file from a newer app version must not be overwritten.
    @ObservationIgnored private var menusReadOnly = false

    private init() {
        store = try? FileStore.appDefault()
        load()
        activities.onActivated = { [weak self] step in
            Task { await self?.scheduledStepBegan(step) }
        }
        activities.startObserving()
    }

    // MARK: Loading and saving

    private func load() {
        guard let store else {
            message = "保存場所を開けませんでした。メニューは保存されません。"
            menus = PersonalMenus.all()
            return
        }
        do {
            if let saved = try store.loadMenus() {
                menus = saved
            } else {
                menus = PersonalMenus.all()
                try store.saveMenus(menus)
            }
        } catch FileStore.StoreError.unsupportedSchema {
            menusReadOnly = true
            message = "新しいバージョンで保存されたメニューです。このバージョンでは変更を保存しません。"
            menus = []
        } catch {
            menusReadOnly = true
            message = "メニューの読み込みに失敗しました（\(error.localizedDescription)）。上書きしないよう保存を止めています。"
        }
        session = try? store.loadSession()
        settings = (try? store.loadSettings()) ?? SoundSettings()
    }

    private func saveMenus() {
        guard !menusReadOnly else { return }
        do { try store?.saveMenus(menus) } catch { message = "メニューを保存できませんでした：\(error.localizedDescription)" }
    }

    private func saveSession() {
        do { try store?.saveSession(session) } catch { message = "進行状態を保存できませんでした：\(error.localizedDescription)" }
    }

    // MARK: Menus

    func upsert(_ menu: Menu) {
        if let i = menus.firstIndex(where: { $0.id == menu.id }) { menus[i] = menu } else { menus.append(menu) }
        saveMenus()
    }

    func delete(at offsets: IndexSet) {
        menus.remove(atOffsets: offsets)
        saveMenus()
    }

    func moveMenus(from source: IndexSet, to destination: Int) {
        menus.move(fromOffsets: source, toOffset: destination)
        saveMenus()
    }

    // MARK: Session

    func start(_ menu: Menu) async {
        _ = await notifications.requestAuthorization()
        session = Session(menu: menu, at: Date())
        saveSession()
        await sync()
    }

    /// Applies an action from the app screen or a lock-screen button. Returns the rejection, if any.
    @discardableResult
    func perform(_ action: Session.Action, target: Session.Target = .any) async -> Session.Rejection? {
        guard var s = session else { return .finished }
        let before = s.stepIndex
        let rejection = s.apply(action, target: target, at: Date())
        guard rejection == nil else { return rejection }
        session = s
        saveSession()
        if s.stepIndex != before || s.isFinished { Haptics.step(enabled: settings.haptics) }
        await sync()
        return nil
    }

    func handleIntent(_ action: WorkoutIntentAction, first: Int, last: Int) async {
        let target: Session.Target = first <= last ? .range(first...last) : .any
        switch action {
        case .next: await perform(.next, target: target)
        case .start: await perform(.start, target: target)
        case .extendRest: await perform(.extendRest, target: target)
        case .toggle:
            if case .paused = session?.phase { await perform(.resume, target: target) }
            else { await perform(.pause, target: target) }
        }
    }

    /// Called about twice a second while the app is visible.
    func tick() async {
        guard var s = session, !s.isFinished else { return }
        let before = s.stepIndex
        guard s.advance(to: Date()) else { return }
        session = s
        saveSession()
        if s.stepIndex != before { Haptics.step(enabled: settings.haptics) }
        await sync()
    }

    /// The app became active again: catch up with the time that passed.
    func resumeFromBackground() async {
        guard var s = session, !s.isFinished else { return }
        s.advance(to: Date())
        session = s
        saveSession()
        await sync()
    }

    /// A scheduled Live Activity started (the app may only have a moment in the background).
    /// Ending finished steps worked on device; new requests are refused there, so none are made.
    private func scheduledStepBegan(_ step: Int) async {
        await activities.endActivities(before: step)
        guard var s = session, !s.isFinished else { return }
        if s.advance(to: Date()) {
            session = s
            saveSession()
        }
    }

    /// Clears a finished or abandoned session and everything it scheduled.
    func close() async {
        session = nil
        saveSession()
        await sync()
    }

    // MARK: Settings

    func update(_ newSettings: SoundSettings) async {
        settings = newSettings
        do { try store?.saveSettings(newSettings) } catch { message = "設定を保存できませんでした：\(error.localizedDescription)" }
        await sync()
    }

    // MARK: Notifications and Live Activities

    /// Rebuilds notifications and Live Activities from the session state alone, so the three never
    /// disagree. Called after every change.
    private func sync() async {
        guard let s = session, !s.isFinished else {
            await notifications.clearAll()
            await activities.endAll()
            return
        }
        await notifications.replace(with: NotificationPlan.make(for: s, at: Date(), settings: settings))
        let foreground = UIApplication.shared.applicationState == .active
        await activities.apply(ActivityPlan.make(for: s, foreground: foreground), session: s)
    }
}

enum Haptics {
    @MainActor
    static func step(enabled: Bool) {
        guard enabled, UIApplication.shared.applicationState == .active else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

import SwiftUI
import WorkoutCore

struct MenuListView: View {
    @State private var controller = SessionController.shared
    @State private var editing: WorkoutMenu?
    @State private var blocked: WorkoutMenu?

    var body: some View {
        NavigationStack {
            List {
                ForEach(controller.menus) { menu in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(menu.name).font(.title3.bold())
                        Text("\(menu.exercises.count)種目・\(menu.rounds)周")
                            .font(.subheadline).foregroundStyle(.secondary)
                        HStack {
                            Button("開始") { start(menu) }
                                .buttonStyle(.borderedProminent)
                                .accessibilityLabel("\(menu.name)を開始")
                            Button("編集") { editing = menu }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("\(menu.name)を編集")
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { controller.delete(at: $0) }
                .onMove { controller.moveMenus(from: $0, to: $1) }
            }
            .navigationTitle("メニュー")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = newMenu() } label: { Label("メニューを追加", systemImage: "plus") }
                }
            }
            .sheet(item: $editing) { menu in
                MenuEditorView(menu: menu) { controller.upsert($0) }
            }
            .alert("このままでは自動で進められません", isPresented: Binding(get: { blocked != nil },
                                                                 set: { if !$0 { blocked = nil } }),
                   presenting: blocked) { menu in
                Button("時間制を手動開始にして始める") {
                    Task { await controller.start(AutoProgressCheck.manualStartVariant(of: menu)) }
                }
                Button("メニューを編集") { editing = menu }
                Button("キャンセル", role: .cancel) {}
            } message: { menu in
                Text(blockedMessage(menu))
            }
        }
    }

    private func newMenu() -> WorkoutMenu {
        WorkoutMenu(name: "新しいメニュー", rounds: 3, restBetweenExercises: 60, restBetweenRounds: 90,
                    autoStartTimed: false, exercises: [Exercise(name: "腕立て伏せ", amount: .reps(15))])
    }

    private func start(_ menu: WorkoutMenu) {
        if AutoProgressCheck(menu: menu).isAllowed {
            Task { await controller.start(menu) }
        } else {
            blocked = menu
        }
    }

    private func blockedMessage(_ menu: WorkoutMenu) -> String {
        let check = AutoProgressCheck(menu: menu)
        let chain = check.longestChain.map(\.title).joined(separator: " → ")
        return "ロック画面で操作した後、続けて自動で進む区間が\(check.longestChain.count)つあります（表示できるのは\(check.limit)つまで）。\n\n\(chain)\n\n時間制の種目を開始ボタンで始めるようにするか、メニューを直してください。"
    }
}

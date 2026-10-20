import SwiftUI
import WorkoutCore

struct MenuEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var menu: WorkoutMenu
    let onSave: (WorkoutMenu) -> Void
    @State private var editingExercise: Exercise?
    @State private var restWheel: RestWheel?

    private enum RestWheel: String, Identifiable {
        case betweenExercises, betweenRounds
        var id: String { rawValue }
    }

    private var issues: [MenuIssue] { menu.validate() }
    private var check: AutoProgressCheck { AutoProgressCheck(menu: menu) }

    var body: some View {
        NavigationStack {
            Form {
                Section("メニュー") {
                    TextField("メニュー名", text: $menu.name)
                    NumberRow(title: "周回", value: $menu.rounds, range: MenuLimits.rounds, unit: "周")
                }
                Section {
                    WheelValueRow(title: "種目の間", value: DurationLabel.text(menu.restBetweenExercises, field: .rest)) {
                        restWheel = .betweenExercises
                    }
                    WheelValueRow(title: "周回の間", value: DurationLabel.text(menu.restBetweenRounds, field: .rest)) {
                        restWheel = .betweenRounds
                    }
                } header: {
                    Text("休憩")
                } footer: {
                    Text("左右の種目の間も「種目の間」の休憩が入ります。種目ごとに変えたいときは、その種目で設定します。")
                }
                Section {
                    Toggle("時間制の種目を自動で始める", isOn: $menu.autoStartTimed)
                } footer: {
                    Text("オフのときは、休憩のあと「開始」を押してから時間制の種目が始まります。")
                }
                Section {
                    ForEach(menu.exercises) { exercise in
                        Button { editingExercise = exercise } label: { ExerciseRow(exercise: exercise) }
                            .foregroundStyle(.primary)
                    }
                    .onDelete { menu.exercises.remove(atOffsets: $0) }
                    .onMove { menu.exercises.move(fromOffsets: $0, toOffset: $1) }
                    Button {
                        editingExercise = Exercise(name: "", amount: .reps(15))
                    } label: {
                        Label("種目を追加", systemImage: "plus.circle")
                    }
                } header: {
                    HStack {
                        Text("種目（上から順に実施）")
                        Spacer()
                        EditButton().font(.caption)
                    }
                }
                Section("自動進行のチェック") {
                    if check.isAllowed {
                        Label("このメニューはロック画面だけで最後まで進められます", systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    } else {
                        Label("続けて自動で進む区間が\(check.longestChain.count)つあり、上限（\(check.limit)つ）を超えています",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(check.longestChain.map(\.title).joined(separator: " → ")).font(.footnote)
                        Text("開始時に「時間制を手動開始にして始める」を選ぶか、休憩・時間制の並びを短くしてください。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if !issues.isEmpty {
                    Section("直してください") {
                        ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                            Text(describe(issue)).foregroundStyle(.red)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .navigationTitle("メニュー編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        menu.name = menu.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(menu)
                        dismiss()
                    }
                    .disabled(!issues.isEmpty)
                }
            }
            .sheet(item: $restWheel) { wheel in
                switch wheel {
                case .betweenExercises:
                    DurationPickerSheet(title: "種目の間の休憩", field: .rest, initial: menu.restBetweenExercises) {
                        menu.restBetweenExercises = $0
                    }
                case .betweenRounds:
                    DurationPickerSheet(title: "周回の間の休憩", field: .rest, initial: menu.restBetweenRounds) {
                        menu.restBetweenRounds = $0
                    }
                }
            }
            .sheet(item: $editingExercise) { exercise in
                ExerciseEditorView(exercise: exercise, defaultRest: menu.restBetweenExercises) { edited in
                    if let i = menu.exercises.firstIndex(where: { $0.id == edited.id }) {
                        menu.exercises[i] = edited
                    } else {
                        menu.exercises.append(edited)
                    }
                }
            }
        }
    }

    private func describe(_ issue: MenuIssue) -> String {
        switch issue {
        case .emptyName: return "メニュー名を入れてください"
        case .nameTooLong: return "メニュー名は40文字までです"
        case .roundsOutOfRange: return "周回は1〜20周です"
        case .restOutOfRange: return "休憩は0秒〜30分です"
        case .noExercises: return "種目を1つ以上入れてください"
        case .tooManyExercises: return "種目は50個までです"
        case .exerciseNameEmpty(let i): return "\(i + 1)番目の種目に名前を入れてください"
        case .exerciseNameTooLong(let i): return "\(i + 1)番目の種目名は40文字までです"
        case .amountOutOfRange(let i): return "\(i + 1)番目の回数・時間を確認してください"
        case .overrideOutOfRange(let i): return "\(i + 1)番目の休憩は0秒〜30分です"
        }
    }
}

struct ExerciseRow: View {
    let exercise: Exercise
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(exercise.name.isEmpty ? "（名前なし）" : exercise.name)
                if let rest = exercise.restAfterOverride {
                    Text("この後の休憩 \(Format.duration(rest))").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(exercise.amount.label).foregroundStyle(.secondary).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

struct ExerciseEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var exercise: Exercise
    let defaultRest: Int
    let onSave: (Exercise) -> Void

    @State private var isTimed = false
    @State private var reps = 15
    @State private var seconds = 30
    @State private var overridesRest = false
    @State private var rest = 15
    @State private var wheel: ExerciseWheel?

    private enum ExerciseWheel: String, Identifiable {
        case reps, time, rest
        var id: String { rawValue }
    }

    init(exercise: Exercise, defaultRest: Int, onSave: @escaping (Exercise) -> Void) {
        _exercise = State(initialValue: exercise)
        self.defaultRest = defaultRest
        self.onSave = onSave
        switch exercise.amount {
        case .reps(let n): _isTimed = State(initialValue: false); _reps = State(initialValue: n)
        case .seconds(let s): _isTimed = State(initialValue: true); _seconds = State(initialValue: s)
        }
        _overridesRest = State(initialValue: exercise.restAfterOverride != nil)
        _rest = State(initialValue: exercise.restAfterOverride ?? defaultRest)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("種目") {
                    TextField("種目名（例：ブルガリアンスクワット右）", text: $exercise.name)
                    Picker("運動量", selection: $isTimed) {
                        Text("回数").tag(false)
                        Text("時間").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if isTimed {
                        WheelValueRow(title: "時間", value: DurationLabel.text(seconds, field: .exercise)) { wheel = .time }
                    } else {
                        WheelValueRow(title: "回数", value: "\(reps)回") { wheel = .reps }
                    }
                }
                Section {
                    Toggle("この種目の後の休憩を変える", isOn: $overridesRest)
                    if overridesRest {
                        WheelValueRow(title: "休憩", value: DurationLabel.text(rest, field: .rest)) { wheel = .rest }
                    }
                } footer: {
                    Text("周の最後の種目では、周回の間の休憩が優先されます。")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .keyboardDoneButton()
            .sheet(item: $wheel) { target in
                switch target {
                case .reps:
                    RepsPickerSheet(title: "回数", initial: reps) { reps = $0 }
                case .time:
                    DurationPickerSheet(title: "時間", field: .exercise, initial: seconds) { seconds = $0 }
                case .rest:
                    DurationPickerSheet(title: "この種目の後の休憩", field: .rest, initial: rest) { rest = $0 }
                }
            }
            .navigationTitle(exercise.name.isEmpty ? "種目を追加" : "種目を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("決定") {
                        exercise.name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        exercise.amount = isTimed ? .seconds(seconds) : .reps(reps)
                        exercise.restAfterOverride = overridesRest ? rest : nil
                        onSave(exercise)
                        dismiss()
                    }
                    .disabled(exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

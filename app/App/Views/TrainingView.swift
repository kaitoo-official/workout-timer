import SwiftUI
import WorkoutCore

/// Exercise and rest screen (MVP仕様「運動中」「休憩中」). Progress comes from the session's end
/// times; the 0.5 s loop only asks the controller to catch up and redraw.
struct TrainingView: View {
    @State private var controller = SessionController.shared
    @State private var confirmFinish = false

    var body: some View {
        if let session = controller.session, let step = session.currentStep {
            let plan = session.plan
            VStack(spacing: 20) {
                header(session, step, plan)
                Spacer(minLength: 0)
                Text(step.isRest ? "休憩" : step.title)
                    .font(.system(size: 40, weight: .bold))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .accessibilityAddTraits(.isHeader)
                amount(session, step)
                nextLine(step, plan)
                Spacer(minLength: 0)
                primaryButtons(session, step)
                secondaryButtons(session, step)
            }
            .padding()
            .task {
                while !Task.isCancelled {
                    await controller.tick()
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
            .confirmationDialog("トレーニングを途中で終了しますか？", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("終了する", role: .destructive) { Task { await controller.perform(.finish) } }
                Button("続ける", role: .cancel) {}
            }
        }
    }

    private func header(_ session: Session, _ step: Step, _ plan: Plan) -> some View {
        HStack {
            Text(session.menu.name).font(.headline)
            Spacer()
            Text("\(step.round)/\(plan.rounds)周目").font(.headline).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func amount(_ session: Session, _ step: Step) -> some View {
        switch session.phase {
        case .waitingCompletion:
            Text(step.amountLabel)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("終わったら「完了」").font(.title3).foregroundStyle(.secondary)
        case .waitingStart:
            Text(step.amountLabel)
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("準備できたら「開始」").font(.title3).foregroundStyle(.secondary)
        case .running(_, let endAt):
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                let remaining = endAt.timeIntervalSince(context.date)
                Text(Format.clock(remaining))
                    .font(.system(size: remaining <= 5.5 ? 110 : 88, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(remaining <= 5.5 ? Color.orange : Color.primary)
                    .contentTransition(.numericText(countsDown: true))
                    .accessibilityLabel("残り\(Int(max(0, remaining).rounded(.up)))秒")
            }
        case .paused(let remaining):
            Text(Format.clock(remaining))
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("一時停止中").font(.title3).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func nextLine(_ step: Step, _ plan: Plan) -> some View {
        if step.isRest, let next = plan.nextExercise(after: step.index) {
            Text("次：\(next.title)　\(next.amountLabel)").font(.title2.bold())
        } else if step.index + 1 < plan.steps.count {
            let next = plan.steps[step.index + 1]
            let after = next.isRest ? plan.nextExercise(after: next.index) : next
            Text("次：\(next.isRest ? "\(next.title) → " : "")\(after?.title ?? "")")
                .font(.title3).foregroundStyle(.secondary)
        } else {
            Text("これが最後の種目です").font(.title3).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func primaryButtons(_ session: Session, _ step: Step) -> some View {
        let target = Session.Target.step(step.index)
        switch session.phase {
        case .waitingCompletion:
            big("完了して次へ", "checkmark") { _ = await controller.perform(.complete, target: target) }
        case .waitingStart:
            big("開始", "play.fill") { _ = await controller.perform(.start, target: target) }
        case .running:
            HStack {
                big("一時停止", "pause.fill") { _ = await controller.perform(.pause, target: target) }
                if step.isRest {
                    big("+30秒", "goforward.30") { _ = await controller.perform(.extendRest, target: target) }
                }
            }
        case .paused:
            HStack {
                big("再開", "play.fill") { _ = await controller.perform(.resume, target: target) }
                if step.isRest {
                    big("+30秒", "goforward.30") { _ = await controller.perform(.extendRest, target: target) }
                }
            }
        }
    }

    private func secondaryButtons(_ session: Session, _ step: Step) -> some View {
        HStack {
            Button(step.isRest ? "休憩スキップ" : "種目スキップ") {
                Task { await controller.perform(.skip, target: .step(step.index)) }
            }
            Spacer()
            Button("取消") { Task { await controller.perform(.undo) } }
                .disabled(!session.canUndo)
                .accessibilityHint("直前の完了・スキップ・開始・延長を戻します")
            Spacer()
            Button("終了", role: .destructive) { confirmFinish = true }
        }
        .buttonStyle(.bordered)
    }

    private func big(_ title: String, _ icon: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: icon)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
    }
}

struct FinishView: View {
    @State private var controller = SessionController.shared
    let session: Session

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: session.ending == .completed ? "checkmark.seal.fill" : "flag.checkered")
                .font(.system(size: 72))
                .foregroundStyle(session.ending == .completed ? .green : .orange)
                .accessibilityHidden(true)
            Text(session.ending == .completed ? "おつかれさまでした" : "途中で終了しました")
                .font(.largeTitle.bold())
            Text(session.menu.name).font(.title2)
            VStack(spacing: 8) {
                Text("完了した種目：\(session.completedExercises)")
                Text("スキップした種目：\(session.skippedExercises)")
            }
            .font(.title3)
            Text("運動の記録は Apple Watch のワークアウトで残してください。")
                .font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Button {
                Task { await controller.close() }
            } label: {
                Text("ホームへ").font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

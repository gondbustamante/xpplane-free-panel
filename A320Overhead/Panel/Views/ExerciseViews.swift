import SwiftUI
import XPlaneKit

/// Exercises in the sidebar: level and best stars; a tap opens the briefing.
struct ExerciseList: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if model.exercises.isEmpty {
            Text("Sin ejercicios en mapping/exercises.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        ForEach(model.exercises) { exercise in
            Button {
                model.exerciseBriefingID = exercise.id
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "stopwatch")
                        .foregroundStyle(PanelTheme.checklistCyan)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(exercise.title)
                            .font(.callout)
                            .lineLimit(1)
                        if let level = exercise.level {
                            Text(level)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 4)
                    if let best = model.bestResult(of: exercise.id) {
                        StarsView(stars: best.stars, size: 10)
                    }
                }
            }
            .buttonStyle(.plain)
            .contextMenu {
                if model.exerciseResults[exercise.id] != nil {
                    Button("Borrar resultados", systemImage: "trash", role: .destructive) {
                        model.deleteResults(of: exercise.id)
                    }
                }
            }
        }
    }
}

struct StarsView: View {
    let stars: Int
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: size * 0.2) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < stars ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(index < stars ? PanelTheme.checklistAmber : Color.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stars) de 3 estrellas")
    }
}

/// Before a run: what it trains, the starting state, the target, the mode and past results.
struct ExerciseBriefingSheet: View {
    let exercise: ExerciseDefinition
    @Environment(PanelModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var mode: ExerciseMode = .guided
    @State private var prepare = true
    @State private var confirmDelete = false

    private var steps: [ExerciseStep] { model.exerciseSteps(exercise, mode: mode) }
    private var examAvailable: Bool { !model.exerciseSteps(exercise, mode: .exam).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let summary = exercise.summary {
                        Text(summary)
                    }
                    if let start = exercise.start {
                        LabeledContent("Situación inicial") { Text(start).multilineTextAlignment(.trailing) }
                    }
                    LabeledContent("Tiempo objetivo", value: ExerciseFormat.time(Double(exercise.targetSeconds)))
                    LabeledContent("Procedimientos") {
                        Text(exercise.procedures.compactMap { model.procedure($0)?.title }.joined(separator: " · "))
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section {
                    Picker("Modo", selection: $mode) {
                        Text("Guiado").tag(ExerciseMode.guided)
                        Text("Examen").tag(ExerciseMode.exam)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!examAvailable)
                    Text(mode == .guided
                         ? "Con el checklist a la vista y todos los pasos, incluidos los que se marcan a mano."
                         : "Sin checklist: haz de memoria los \(steps.count) pasos que la app comprueba sola. «Pista» enseña el siguiente, a cambio de puntos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Modo")
                } footer: {
                    if !examAvailable {
                        Text("Este ejercicio no tiene pasos que la app pueda comprobar sola: solo hay modo guiado.")
                    }
                }
                Section("Puntuación") {
                    Text("Empiezas con 100 puntos. Pierdes medio punto por cada 1 % por encima del tiempo objetivo (máximo 30), \(ExerciseScoring.undonePenalty) por deshacer un paso, \(ExerciseScoring.outOfOrderPenalty) por saltarte el orden, \(ExerciseScoring.wrongControlPenalty) por mover un mando que no toca y \(ExerciseScoring.hintPenalty) por cada pista («Mostrar en el panel», «Poner» o marcar a mano un paso que el avión no confirma).")
                        .font(.footnote)
                    Text("90 o más: ★★★ · 75: ★★ · 50: ★")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let results = model.exerciseResults[exercise.id], !results.isEmpty {
                    Section {
                        ForEach(Array(results.prefix(5).enumerated()), id: \.offset) { _, result in
                            HStack {
                                StarsView(stars: result.stars, size: 11)
                                Text("\(result.score) pts")
                                    .monospacedDigit()
                                Spacer()
                                Text(ExerciseFormat.time(result.elapsed))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                Text(result.mode == .exam ? "Examen" : "Guiado")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(result.date, format: .dateTime.day().month())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Borrar mis resultados", role: .destructive) { confirmDelete = true }
                    } header: {
                        Text("Tus resultados")
                    }
                }
                Section {
                    if model.status == .connected {
                        if model.canPrepare(exercise) {
                            Toggle(isOn: $prepare) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Preparar el avión antes de empezar")
                                    Text(preparationText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button {
                            model.beginExercise(exercise.id, mode: examAvailable ? mode : .guided, prepare: prepare)
                            dismiss()
                        } label: {
                            Label("Empezar", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Text("Los ejercicios leen la posición de los mandos: conecta con X-Plane o usa el modo demo.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            model.startDemo()
                        } label: {
                            Label("Conectar en modo demo", systemImage: "play.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.status.isActive)
                    }
                }
            }
            .navigationTitle(exercise.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .confirmationDialog("¿Borrar los resultados de \(exercise.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Borrar", role: .destructive) { model.deleteResults(of: exercise.id) }
            }
        }
        .preferredColorScheme(.dark)
    }

    /// What preparing does: cold and dark (demo) and the procedures applied.
    private var preparationText: String {
        var parts: [String] = []
        if exercise.startsColdAndDark && model.canResetAircraft { parts.append("Cold & Dark") }
        parts += (exercise.setup ?? []).compactMap { model.procedure($0)?.title }
        let steps = parts.joined(separator: " → ")
        return "\(steps). Así empiezas en la situación inicial del ejercicio y no arrastras pasos pendientes de antes."
    }
}

/// Strip under the connection bar while an exercise runs: clock, progress, mistakes and hints.
struct ExerciseBar: View {
    @Environment(PanelModel.self) private var model
    @State private var confirmAbandon = false
    @State private var confirmRestart = false

    var body: some View {
        if let preparing = model.preparingExercise {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Preparando el avión para «\(preparing.title)»: no toques los mandos.")
                    .font(.footnote)
                Spacer(minLength: 0)
            }
            .foregroundStyle(PanelTheme.checklistCyan)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(PanelTheme.checklistCyan.opacity(0.10))
        }
        if let run = model.exerciseRun, run.isRunning {
            let tracker = run.tracker
            let target = Double(tracker.definition.targetSeconds)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    Image(systemName: "stopwatch.fill")
                    Text(tracker.definition.title)
                        .font(.footnote.weight(.semibold))
                        .lineLimit(1)
                    Text(tracker.mode == .exam ? "EXAMEN" : "GUIADO")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .overlay(Capsule().strokeBorder(PanelTheme.checklistCyan.opacity(0.6), lineWidth: 1))
                    Spacer(minLength: 8)
                    TimelineView(.periodic(from: run.startedAt, by: 1)) { context in
                        let elapsed = model.exerciseElapsed(at: context.date)
                        Text("\(ExerciseFormat.time(elapsed)) / \(ExerciseFormat.time(target))")
                            .monospacedDigit()
                            .foregroundStyle(elapsed > target ? PanelTheme.checklistAmber : PanelTheme.checklistCyan)
                    }
                    Label("\(tracker.doneCount)/\(tracker.steps.count)", systemImage: "checklist")
                        .monospacedDigit()
                    Label("\(tracker.mistakes.count)", systemImage: "xmark.circle")
                        .foregroundStyle(tracker.mistakes.isEmpty ? Color.secondary : PanelTheme.checklistAmber)
                        .monospacedDigit()
                    Label("\(tracker.hints)", systemImage: "lightbulb")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if tracker.mode == .exam {
                        Button("Pista") { model.revealExerciseStep() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Button("Reiniciar") { confirmRestart = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("Abandonar", role: .destructive) { confirmAbandon = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .font(.footnote)
                if tracker.mode == .exam, let current = tracker.currentStep, run.revealed.contains(current) {
                    let item = tracker.steps[current].item
                    Label("\(item.challenge) … \(item.response)", systemImage: "lightbulb.fill")
                        .font(.footnote.monospaced())
                }
                // The latest mistake stays visible a few seconds, so the cause is clear.
                if let mistake = tracker.mistakes.last {
                    TimelineView(.periodic(from: run.startedAt, by: 1)) { context in
                        if model.exerciseElapsed(at: context.date) - mistake.at < 5 {
                            Label(model.text(for: mistake), systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(PanelTheme.checklistAmber)
                        }
                    }
                }
            }
            .foregroundStyle(PanelTheme.checklistCyan)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(PanelTheme.checklistCyan.opacity(0.10))
            .confirmationDialog("¿Abandonar el ejercicio?", isPresented: $confirmAbandon, titleVisibility: .visible) {
                Button("Abandonar", role: .destructive) { model.abandonExercise() }
            } message: {
                Text("No se guarda resultado.")
            }
            .confirmationDialog("¿Reiniciar el ejercicio?", isPresented: $confirmRestart, titleVisibility: .visible) {
                if model.canPrepare(tracker.definition) {
                    Button("Reiniciar en la situación inicial") { model.repeatExercise(prepare: true) }
                }
                Button("Reiniciar desde el estado actual") { model.repeatExercise() }
            } message: {
                Text("El cronómetro vuelve a cero y este intento no se guarda.")
            }
        }
    }
}

/// End of a run: stars, score, time against the target and what went wrong.
struct ExerciseResultSheet: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        NavigationStack {
            if let run = model.exerciseRun, let result = run.result {
                List {
                    Section {
                        VStack(spacing: 10) {
                            StarsView(stars: result.stars, size: 34)
                            Text("\(result.score) puntos")
                                .font(.largeTitle.weight(.bold))
                                .monospacedDigit()
                            Text(verdict(result))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    Section("Desglose") {
                        row("Tiempo", "\(ExerciseFormat.time(result.elapsed)) de \(ExerciseFormat.time(result.target))",
                            penalty: ExerciseScoring.timePenalty(elapsed: result.elapsed, target: result.target))
                        row("Pasos deshechos", "\(result.count(.undone))",
                            penalty: result.count(.undone) * ExerciseScoring.undonePenalty)
                        row("Fuera de orden", "\(result.count(.outOfOrder))",
                            penalty: result.count(.outOfOrder) * ExerciseScoring.outOfOrderPenalty)
                        row("Mandos que no tocaban", "\(result.count(.wrongControl))",
                            penalty: result.count(.wrongControl) * ExerciseScoring.wrongControlPenalty)
                        row("Pistas", "\(result.hints)", penalty: result.hints * ExerciseScoring.hintPenalty)
                    }
                    if !result.mistakes.isEmpty {
                        Section("Qué repasar") {
                            ForEach(Array(result.mistakes.enumerated()), id: \.offset) { _, mistake in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(ExerciseFormat.time(mistake.at))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, alignment: .leading)
                                    Text(model.text(for: mistake))
                                }
                            }
                            Text("Activa el modo aprender y toca esos mandos para ver por qué van en ese orden y en esa posición.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle(run.tracker.definition.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { model.closeExerciseResult() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if model.canPrepare(run.tracker.definition) {
                            Menu("Repetir") {
                                Button("Repetir en la situación inicial") { model.repeatExercise(prepare: true) }
                                Button("Repetir desde el estado actual") { model.repeatExercise() }
                            } primaryAction: {
                                model.repeatExercise(prepare: true)
                            }
                        } else {
                            Button("Repetir") { model.repeatExercise() }
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(_ title: String, _ value: String, penalty: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(penalty > 0 ? "−\(penalty)" : "0")
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
                .foregroundStyle(penalty > 0 ? PanelTheme.checklistAmber : PanelTheme.checklistGreen)
        }
    }

    private func verdict(_ result: ExerciseResult) -> String {
        switch result.stars {
        case 3: return "Limpio y a tiempo. Prueba el modo examen o un ejercicio más largo."
        case 2: return "Bien. Repasa los puntos de abajo y repite."
        case 1: return "Completado, con margen de mejora."
        default: return "Repite en modo guiado y apóyate en el modo aprender."
        }
    }
}

enum ExerciseFormat {
    /// "m:ss".
    static func time(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

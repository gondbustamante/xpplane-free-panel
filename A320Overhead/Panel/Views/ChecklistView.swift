import SwiftUI
import XPlaneKit

/// Column beside the panels with the active flow or checklist, styled after the Airbus
/// electronic checklist: cyan to do, green done, the current line framed.
struct ChecklistColumn: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        Group {
            if let procedure = model.activeProcedure {
                ChecklistRunner(procedure: procedure)
            } else {
                ContentUnavailableView("Sin procedimientos", systemImage: "checklist",
                                       description: Text("Añade archivos JSON en mapping/procedures."))
            }
        }
        .background(PanelTheme.checklistSurface)
    }
}

private struct ChecklistRunner: View {
    let procedure: Procedure
    @Environment(PanelModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        let progress = model.progress(of: procedure)
        let current = model.currentItem(in: procedure)
        let complete = model.isComplete(procedure)
        VStack(spacing: 0) {
            ChecklistHeader(procedure: procedure, done: progress.done, total: progress.total)
            if model.status != .connected && procedure.items.contains(where: \.isSensed) {
                Label("Sin conexión: marca a mano los ítems detectados.", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.caption)
                    .foregroundStyle(PanelTheme.checklistAmber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(PanelTheme.checklistAmber.opacity(0.10))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(Array(procedure.items.enumerated()), id: \.offset) { index, item in
                            ChecklistRow(procedure: procedure, index: index, item: item, isCurrent: index == current)
                                .id(index)
                        }
                        if complete {
                            CompleteBanner(procedure: procedure)
                                .id("complete")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 12)
                }
                .onChange(of: current) { _, line in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if let line { proxy.scrollTo(line, anchor: .center) } else { proxy.scrollTo("complete") }
                    }
                }
            }
            Divider()
            footer(complete: complete)
        }
        .sensoryFeedback(.success, trigger: complete) { _, now in now }
        .sensoryFeedback(.selection, trigger: progress.done)
        .confirmationDialog("¿Reiniciar \(procedure.title)?", isPresented: $confirmReset, titleVisibility: .visible) {
            if model.canResetAircraft {
                Button("Reiniciar y avión en Cold & Dark", role: .destructive) {
                    model.resetProcedures([procedure], aircraft: true)
                }
            }
            Button("Desmarcar los ítems marcados a mano", role: .destructive) { model.resetTicks(of: procedure) }
        } message: {
            Text(model.canResetAircraft
                 ? "Los ítems detectados siguen a los mandos: para empezarlos de nuevo, vuelve el avión de la demo a Cold & Dark."
                 : "Se desmarcan los ítems marcados a mano. Los detectados siguen a los mandos del simulador.")
        }
    }

    private func footer(complete: Bool) -> some View {
        HStack(spacing: 10) {
            Button {
                confirmReset = true
            } label: {
                Label("Reiniciar", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .help("Reiniciar \(procedure.title)")
            if let previous = model.previous(before: procedure) {
                Button {
                    model.open(procedure: previous.id)
                } label: {
                    Label("Anterior", systemImage: "chevron.left")
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .help("Anterior: \(previous.title)")
                .accessibilityLabel("Anterior: \(previous.title)")
            }
            Spacer(minLength: 0)
            if let next = model.next(after: procedure) {
                Button {
                    model.open(procedure: next.id)
                } label: {
                    Label("Siguiente: \(next.title)", systemImage: "chevron.right")
                        .labelStyle(TrailingIconLabelStyle())
                        .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .tint(complete ? PanelTheme.checklistGreen.opacity(0.85) : .accentColor)
            }
        }
        .controlSize(.regular)
        .padding(12)
    }
}

/// Procedure picker, kind, phase and progress.
private struct ChecklistHeader: View {
    let procedure: Procedure
    let done: Int
    let total: Int
    @Environment(PanelModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(phaseGroups, id: \.id) { group in
                    Section(group.title) {
                        ForEach(group.procedures) { item in
                            Button {
                                model.open(procedure: item.id)
                            } label: {
                                Label(item.title, systemImage: model.isComplete(item) ? "checkmark.circle.fill" : ProcedureStyle.icon(item.kind))
                            }
                        }
                    }
                }
            } label: {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(caption)
                            .font(.caption2.weight(.semibold))
                            .tracking(0.8)
                            .foregroundStyle(PanelTheme.checklistCyan)
                        Text(procedure.title)
                            .font(procedure.kind == .checklist ? .title3.weight(.semibold).monospaced() : .title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            if let summary = procedure.summary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint(done == total ? PanelTheme.checklistGreen : PanelTheme.checklistCyan)
                Text("\(done)/\(total)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(done == total ? PanelTheme.checklistGreen : .secondary)
            }
        }
        .padding(16)
    }

    private var caption: String {
        let kind = ProcedureStyle.kindTitle(procedure.kind).uppercased()
        guard let phase = model.layout.phases.first(where: { $0.id == procedure.phase }) else { return kind }
        return "\(kind) · \(phase.title.uppercased())"
    }

    private var phaseGroups: [ProcedureStyle.PhaseGroup] {
        ProcedureStyle.groups(model.procedures, phases: model.layout.phases)
    }
}

/// One line: tick box, challenge, dotted leader, response; note, sub-lines and sensing below.
private struct ChecklistRow: View {
    let procedure: Procedure
    let index: Int
    let item: ProcedureItem
    let isCurrent: Bool
    @Environment(PanelModel.self) private var model
    @State private var showWhy = false

    var body: some View {
        let done = model.isDone(procedure, item: index)
        let sensed = model.sensedState(of: item)
        let colour = done ? PanelTheme.checklistGreen : (isCurrent ? PanelTheme.checklistCyan : .white.opacity(0.9))
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: done ? "checkmark.square.fill" : "square")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(done ? PanelTheme.checklistGreen : (isCurrent ? PanelTheme.checklistCyan : .white.opacity(0.45)))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.challenge)
                        .layoutPriority(1)
                    DotLeader()
                        .stroke(colour.opacity(0.55), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [0.1, 4.5]))
                        .frame(minWidth: 10, maxHeight: 2)
                    Text(item.response)
                        .foregroundStyle(done ? PanelTheme.checklistGreen : PanelTheme.checklistCyan)
                        .multilineTextAlignment(.trailing)
                        .layoutPriority(1)
                }
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(colour)
                if let sub = item.sub {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(sub, id: \.self) { line in
                            Text("– \(line)")
                        }
                    }
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(colour.opacity(0.85))
                    .padding(.leading, 12)
                }
                if let note = item.note, isCurrent || !done {
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let why = item.why, isCurrent || showWhy {
                    Label(why, systemImage: "lightbulb")
                        .font(.footnote)
                        .foregroundStyle(PanelTheme.checklistCyan.opacity(0.85))
                }
                metaLine(sensed: sensed, done: done)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCurrent ? PanelTheme.checklistCyan.opacity(0.08) : .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isCurrent ? PanelTheme.checklistCyan.opacity(0.9) : .clear, lineWidth: 1.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { model.toggleTick(procedure, item: index) }
        .accessibilityAction(named: done ? "Desmarcar" : "Marcar como hecho") { model.toggleTick(procedure, item: index) }
        .contextMenu {
            Button(model.isTicked(procedure, item: index) ? "Desmarcar" : "Marcar como hecho",
                   systemImage: model.isTicked(procedure, item: index) ? "square" : "checkmark.square") {
                model.toggleTick(procedure, item: index)
            }
            if let control = model.controlToLocate(for: item) {
                Button("Mostrar en el panel", systemImage: "scope") { model.locate(control: control) }
            } else if let panel = item.panels?.first {
                Button("Mostrar en el panel", systemImage: "scope") { model.locate(panel: panel) }
            }
            if model.canApply(item) {
                Button("Poner en \(item.response)", systemImage: "hand.tap") { model.apply(item) }
            }
            if let control = item.checks?.first?.control {
                Button("Explicar el mando", systemImage: "graduationcap") { model.explain(control: control) }
            }
        }
    }

    /// Optional tag, what the simulator reads, and the locate / apply shortcuts.
    @ViewBuilder
    private func metaLine(sensed: ProcedureCheckState, done: Bool) -> some View {
        let locateControl = model.controlToLocate(for: item)
        let locatePanel = item.panels?.first
        let mismatches = sensed == .unsatisfied ? model.mismatches(in: item) : []
        let showsSensing = sensed != .notSensed && !(done && sensed != .satisfied)
        let offersWhy = item.why != nil && !isCurrent
        if item.isOptional || showsSensing || locateControl != nil || locatePanel != nil || offersWhy {
            HStack(spacing: 8) {
                if item.isOptional {
                    Tag(text: "SI APLICA", colour: .secondary)
                }
                if offersWhy {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showWhy.toggle() }
                    } label: {
                        Label(showWhy ? "Ocultar" : "¿Por qué?", systemImage: "lightbulb")
                    }
                    .buttonStyle(.bordered)
                }
                if showsSensing {
                    switch sensed {
                    case .satisfied:
                        Label("Detectado", systemImage: "dot.radiowaves.left.and.right")
                            .foregroundStyle(PanelTheme.checklistGreen.opacity(0.85))
                    case .unsatisfied:
                        Label(mismatches.isEmpty ? "Pendiente" : mismatches.joined(separator: " · "),
                              systemImage: "exclamationmark.circle")
                            .foregroundStyle(PanelTheme.checklistAmber)
                            .lineLimit(2)
                    case .unknown:
                        Label("Esperando al simulador", systemImage: "hourglass")
                            .foregroundStyle(.secondary)
                    case .notSensed:
                        EmptyView()
                    }
                }
                Spacer(minLength: 0)
                if locateControl != nil || locatePanel != nil, !done || isCurrent {
                    Button {
                        if let locateControl { model.locate(control: locateControl) } else if let locatePanel { model.locate(panel: locatePanel) }
                    } label: {
                        Image(systemName: "scope")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Mostrar en el panel")
                }
                if model.canApply(item) {
                    Button {
                        model.apply(item)
                    } label: {
                        Label("Poner", systemImage: "hand.tap")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PanelTheme.checklistCyan.opacity(0.8))
                }
            }
            .font(.caption)
            .controlSize(.mini)
        }
    }
}

private struct CompleteBanner: View {
    let procedure: Procedure

    var body: some View {
        Text(procedure.kind == .checklist ? "\(procedure.title) CHECKLIST COMPLETE" : "PROCEDIMIENTO COMPLETADO")
            .font(.system(size: 14, weight: .semibold, design: .monospaced))
            .foregroundStyle(PanelTheme.checklistGreen)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(PanelTheme.checklistGreen.opacity(0.6), lineWidth: 1)
            }
            .padding(.top, 8)
    }
}

private struct Tag: View {
    let text: String
    let colour: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(colour)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(colour.opacity(0.6), lineWidth: 1))
    }
}

/// Horizontal line along the bottom of its frame, stroked as dots between challenge and response.
private struct DotLeader: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.title
            configuration.icon
        }
    }
}

/// Names, icons and phase grouping shared by the sidebar and the checklist column.
enum ProcedureStyle {
    struct PhaseGroup: Identifiable {
        let id: String
        let title: String
        let icon: String
        var procedures: [Procedure]
    }

    static func icon(_ kind: Procedure.Kind) -> String {
        switch kind {
        case .flow: return "list.bullet.rectangle.portrait"
        case .checklist: return "checklist"
        }
    }

    static func kindTitle(_ kind: Procedure.Kind) -> String {
        switch kind {
        case .flow: return "Procedimiento"
        case .checklist: return "Checklist"
        }
    }

    /// Procedures grouped by flight phase, in the order they first appear (flight order).
    static func groups(_ procedures: [Procedure], phases: [FlightPhase]) -> [PhaseGroup] {
        var groups: [PhaseGroup] = []
        for procedure in procedures {
            let id = procedure.phase ?? "other"
            if let index = groups.firstIndex(where: { $0.id == id }) {
                groups[index].procedures.append(procedure)
            } else {
                let phase = phases.first { $0.id == id }
                groups.append(PhaseGroup(id: id, title: phase?.title ?? "Otros",
                                         icon: phase?.icon ?? "list.bullet", procedures: [procedure]))
            }
        }
        return groups
    }
}

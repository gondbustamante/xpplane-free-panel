import SwiftUI
import XPlaneKit

/// Column beside the panels: the checklist or, with an OFP, the MCDU guide.
struct InspectorColumn: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker("Columna", selection: $model.inspectorPanel) {
                Text("Checklist").tag(PanelModel.InspectorPanel.checklist)
                Text("Guía MCDU").tag(PanelModel.InspectorPanel.mcduGuide)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .disabled(model.isExamRunning)
            switch model.inspectorPanel {
            case .checklist: ChecklistColumn()
            case .mcduGuide: MCDUGuideColumn()
            }
        }
        .background(PanelTheme.checklistSurface)
    }
}

/// Walks the SimBrief OFP into the MCDU: page and key, value to type, where it is in the OFP,
/// why it goes in and what it changes, with ToLiss confirming what it can read.
struct MCDUGuideColumn: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if let ofp = model.ofp {
            loaded(ofp)
        } else {
            OFPLoader()
        }
    }

    private func loaded(_ ofp: SimBriefOFP) -> some View {
        let steps = model.mcduGuideSteps
        let gate = steps.filter { !$0.later }
        let done = gate.filter { model.isGuideDone($0) }.count
        let current = gate.first { !model.isGuideDone($0) && !$0.optional }?.id
            ?? gate.first { !model.isGuideDone($0) }?.id
        let pageTitle = model.mcduPageTitle
        return VStack(spacing: 0) {
            OFPHeader(ofp: ofp, done: done, total: gate.count)
            if !pageTitle.isEmpty {
                Label("En el MCDU: \(pageTitle)", systemImage: "rectangle.and.text.magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(gate) { step in
                            GuideStepCard(step: step, isCurrent: step.id == current,
                                          onMCDUPage: step.screenTitles.contains { pageTitle.uppercased().contains($0) })
                                .id(step.id)
                        }
                        let later = steps.filter(\.later)
                        if !later.isEmpty {
                            Text("EN VUELO")
                                .font(.caption.weight(.semibold))
                                .tracking(0.8)
                                .foregroundStyle(PanelTheme.checklistCyan)
                                .padding(.top, 8)
                            ForEach(later) { step in
                                GuideStepCard(step: step, isCurrent: false,
                                              onMCDUPage: step.screenTitles.contains { pageTitle.uppercased().contains($0) })
                            }
                        }
                        Text("Valores del OFP de SimBrief para simulación. Manda la autorización ATC, el ATIS y la hoja de carga final.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                    }
                    .padding(12)
                }
                .onChange(of: current) { _, id in
                    if let id { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .top) } }
                }
            }
        }
    }
}

/// Flight, route and OFP details, progress and reload.
private struct OFPHeader: View {
    let ofp: SimBriefOFP
    let done: Int
    let total: Int
    @Environment(PanelModel.self) private var model
    @State private var confirmReset = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(ofp.callsign ?? "OFP") · \(ofp.routeTitle)")
                        .font(.headline)
                    Text([ofp.aircraft, ofp.registration, ofp.airac.map { "AIRAC \($0)" },
                          ofp.generated.map { "OFP \($0.formatted(date: .abbreviated, time: .shortened))" }]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("Cargar el último OFP", systemImage: "arrow.clockwise") {
                        Task { await model.loadOFP() }
                    }
                    Button("Reiniciar la guía", systemImage: "arrow.counterclockwise") { confirmReset = true }
                    Button("Quitar el OFP", systemImage: "trash", role: .destructive) { model.clearOFP() }
                } label: {
                    if model.ofpLoading {
                        ProgressView()
                    } else {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            HStack(spacing: 10) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                    .tint(done == total ? PanelTheme.checklistGreen : PanelTheme.checklistCyan)
                Text("\(done)/\(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if let error = model.ofpError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(PanelTheme.checklistAmber)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .confirmationDialog("¿Reiniciar la guía?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reiniciar", role: .destructive) { model.resetGuide() }
        } message: {
            Text("Se desmarcan los pasos marcados a mano. Los que ToLiss confirma siguen al MCDU.")
        }
    }
}

/// One step: page and key, values to type, OFP source, why and what it changes.
private struct GuideStepCard: View {
    let step: MCDUGuideStep
    let isCurrent: Bool
    let onMCDUPage: Bool
    @Environment(PanelModel.self) private var model
    @State private var expanded: Bool?

    var body: some View {
        let done = model.isGuideDone(step)
        let showsDetail = expanded ?? isCurrent
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    model.toggleGuideDone(step)
                } label: {
                    Image(systemName: done ? "checkmark.square.fill" : "square")
                        .font(.system(size: 19))
                        .foregroundStyle(done ? PanelTheme.checklistGreen : (isCurrent ? PanelTheme.checklistCyan : .white.opacity(0.45)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(done ? "Desmarcar" : "Marcar como hecho")
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(step.page)
                            .font(.caption2.weight(.bold).monospaced())
                            .foregroundStyle(PanelTheme.checklistCyan)
                        if onMCDUPage {
                            Text("EN PANTALLA")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(PanelTheme.checklistGreen)
                        }
                        if step.optional {
                            Text("OPCIONAL")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(step.field)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(done ? PanelTheme.checklistGreen : .white)
                    Text(step.location)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let display = step.display {
                Text(display)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
            }
            if !step.entries.isEmpty {
                VStack(spacing: 6) {
                    ForEach(step.entries) { entry in
                        EntryRow(entry: entry)
                    }
                }
            }
            DisclosureGroup(isExpanded: Binding(get: { showsDetail }, set: { expanded = $0 })) {
                VStack(alignment: .leading, spacing: 6) {
                    detail("En el OFP", step.source, icon: "doc.text")
                    detail("Por qué", step.why, icon: "lightbulb")
                    if let affects = step.affects {
                        detail("Qué afecta", affects, icon: "arrow.triangle.branch")
                    }
                }
                .padding(.top, 4)
            } label: {
                Text("Dónde está y por qué")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(PanelTheme.checklistCyan)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCurrent ? PanelTheme.checklistCyan.opacity(0.08) : Color.white.opacity(0.04))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isCurrent ? PanelTheme.checklistCyan.opacity(0.9)
                              : (onMCDUPage && !done ? PanelTheme.checklistCyan.opacity(0.35) : .clear), lineWidth: 1.5)
        }
    }

    private func detail(_ title: String, _ text: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(text).font(.footnote)
            }
        } icon: {
            Image(systemName: icon).foregroundStyle(PanelTheme.checklistCyan)
        }
    }
}

/// A value to type: what goes in the scratchpad, ToLiss's check and the type button.
private struct EntryRow: View {
    let entry: GuideEntry
    @Environment(PanelModel.self) private var model

    var body: some View {
        let result = model.checkResult(entry)
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(entry.value)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(result == true ? PanelTheme.checklistGreen : PanelTheme.checklistCyan)
                    .textSelection(.enabled)
            }
            if let location = entry.location {
                Text(location)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            switch result {
            case .some(true):
                Label("En el MCDU", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(PanelTheme.checklistGreen)
                    .accessibilityLabel("El MCDU tiene este valor")
            case .some(false):
                Label("Distinto", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(PanelTheme.checklistAmber)
            case .none:
                EmptyView()
            }
            Button {
                model.typeIntoMCDU(entry)
            } label: {
                if model.typingEntryID == entry.id {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Teclear", systemImage: "keyboard")
                        .labelStyle(.iconOnly)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.status != .connected)
            .help("Escribe \(entry.value) en el scratchpad; después pulsa la LSK")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.25)))
    }
}

/// No OFP yet: SimBrief user and load button.
private struct OFPLoader: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Label("Guía del MCDU con tu plan de SimBrief", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Text("Carga tu último OFP y la guía te lleva página a página: qué teclear, en qué tecla, dónde está ese dato en el OFP, por qué se introduce y qué afecta. Con ToLiss conectado, comprueba lo que ya está en el MCDU.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                TextField("Usuario de SimBrief o Pilot ID", text: $model.simBriefUser)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                Button {
                    Task { await model.loadOFP() }
                } label: {
                    if model.ofpLoading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Cargar mi último OFP", systemImage: "arrow.down.doc")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.simBriefUser.trimmingCharacters(in: .whitespaces).isEmpty || model.ofpLoading)
                if let error = model.ofpError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(PanelTheme.checklistAmber)
                }
                Text("El Pilot ID está en SimBrief → Account Settings. Genera antes el plan en SimBrief (con el módulo de performance activado para tener V1, VR, V2 y FLEX).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
        }
    }
}

/// Flight plan entry in the sidebar's Vuelo tab.
struct OFPSidebarRow: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        Button {
            model.openMCDUGuide()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundStyle(PanelTheme.checklistCyan)
                    .frame(width: 22)
                if let ofp = model.ofp {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(ofp.callsign ?? "OFP") · \(ofp.routeTitle)")
                            .font(.callout)
                            .lineLimit(1)
                        Text("Guía del MCDU")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    let gate = model.mcduGuideSteps.filter { !$0.later }
                    let done = gate.filter { model.isGuideDone($0) }.count
                    if !gate.isEmpty {
                        Text("\(done)/\(gate.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(done == gate.count ? PanelTheme.checklistGreen : .secondary)
                    }
                } else {
                    Text("Cargar OFP de SimBrief")
                        .font(.callout)
                    Spacer(minLength: 4)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

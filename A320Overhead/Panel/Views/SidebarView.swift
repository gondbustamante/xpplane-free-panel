import SwiftUI
import XPlaneKit

/// The sidebar's three tabs, by what the user is doing: flying a phase with its procedures,
/// picking a cockpit area, or practising (learn mode, exercises, turnaround).
enum SidebarTab: String, CaseIterable, Identifiable {
    case flight
    case cockpit
    case practice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flight: return "Vuelo"
        case .cockpit: return "Cabina"
        case .practice: return "Práctica"
        }
    }
}

/// Comma-separated ids kept in @AppStorage (zone order and expanded groups).
enum StoredIDs {
    static func decode(_ raw: String) -> [String] {
        raw.split(separator: ",").map(String.init)
    }

    static func encode(_ ids: [String]) -> String {
        ids.joined(separator: ",")
    }

    /// `items` in the stored order; ones the order does not know keep their place at the end.
    static func ordered<T>(_ items: [T], by raw: String, id: (T) -> String) -> [T] {
        let order = decode(raw)
        var rank: [String: Int] = [:]
        for (index, id) in order.enumerated() where rank[id] == nil { rank[id] = index }
        return items.enumerated().sorted { lhs, rhs in
            (rank[id(lhs.element)] ?? order.count + lhs.offset) < (rank[id(rhs.element)] ?? order.count + rhs.offset)
        }.map(\.element)
    }

    static func toggled(_ raw: String, _ id: String, on: Bool) -> String {
        var ids = decode(raw).filter { $0 != id }
        if on { ids.append(id) }
        return encode(ids)
    }
}

/// Left column: status and the checklist in progress on top, then three tabs. Vuelo lists the
/// flight phases, each opening its panels and unfolding its procedures; Cabina has the user's
/// panels and the cockpit areas, each unfolding its sections; Práctica gathers learn mode,
/// exercises and the turnaround. The search looks through all of them.
struct SidebarView: View {
    @Environment(PanelModel.self) private var model
    /// Panel being edited; nil panel means "new".
    @State private var editing: EditorTarget?
    @State private var query = ""
    @State private var editMode: EditMode = .inactive
    @State private var confirmResetChecklists = false
    @State private var confirmDeleteResults = false
    @State private var phaseToReset: ProcedureStyle.PhaseGroup?

    @AppStorage("sidebar.tab") private var tabRaw = SidebarTab.flight.rawValue
    /// Disclosure groups (phases, cockpit areas) start closed except the first phase.
    @AppStorage("sidebar.expanded") private var expandedRaw = "flight:cold_dark"
    @AppStorage("sidebar.groupOrder") private var groupOrderRaw = ""

    private struct EditorTarget: Identifiable {
        let id = UUID()
        let panel: CustomPanel?
    }

    private var tab: Binding<SidebarTab> {
        Binding(get: { SidebarTab(rawValue: tabRaw) ?? .flight }, set: { tabRaw = $0.rawValue })
    }

    /// iOS only offers `List(selection:)` with an optional value; keep the last choice on deselect.
    private var selection: Binding<PanelSelection?> {
        Binding(get: { model.selection },
                set: { newValue in if let newValue { model.selection = newValue } })
    }

    private var groups: [PanelGroup] {
        StoredIDs.ordered(model.layout.groups, by: groupOrderRaw, id: \.id)
    }

    /// Procedures grouped by phase, keyed by phase id ("other" for those without one).
    private var proceduresByPhase: [String: ProcedureStyle.PhaseGroup] {
        Dictionary(uniqueKeysWithValues: ProcedureStyle.groups(model.procedures, phases: model.layout.phases).map { ($0.id, $0) })
    }

    private var isEditing: Bool { editMode == .active }
    private var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        List(selection: selection) {
            Section {
                SidebarHeader()
                if let active = model.activeProcedure {
                    ActiveChecklistRow(procedure: active)
                }
                if !isSearching {
                    Picker("Vista", selection: tab) {
                        ForEach(SidebarTab.allCases) { tab in
                            Text(tab.title).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowSeparator(.hidden)
                }
            }
            if isSearching {
                SearchResults(query: query)
            } else {
                switch tab.wrappedValue {
                case .flight: flightTab
                case .cockpit: cockpitTab
                case .practice: practiceTab
                }
            }
        }
        .listStyle(.sidebar)
        .environment(\.editMode, $editMode)
        .searchable(text: $query, placement: .sidebar, prompt: "Buscar paneles, procedimientos y ejercicios")
        .navigationTitle("A320")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isEditing {
                    Button("OK") { withAnimation { editMode = .inactive } }
                        .fontWeight(.semibold)
                } else {
                    if model.selection.isCustom, let panel = model.selectedCustomPanel {
                        Button("Editar panel", systemImage: "slider.horizontal.3") { editing = EditorTarget(panel: panel) }
                    }
                    Menu {
                        if tab.wrappedValue == .cockpit {
                            Button("Ordenar paneles y zonas", systemImage: "arrow.up.arrow.down") {
                                withAnimation { editMode = .active }
                            }
                        }
                        Button("Nuevo panel", systemImage: "plus") { editing = EditorTarget(panel: nil) }
                        Divider()
                        Button("Reiniciar procedimientos…", systemImage: "arrow.counterclockwise", role: .destructive) {
                            confirmResetChecklists = true
                        }
                        Button("Borrar resultados de ejercicios…", systemImage: "trash", role: .destructive) {
                            confirmDeleteResults = true
                        }
                        .disabled(model.exerciseResults.isEmpty)
                    } label: {
                        Label("Opciones", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $editing) { target in
            CustomPanelEditor(panel: target.panel)
        }
        .confirmationDialog("¿Reiniciar todos los procedimientos?", isPresented: $confirmResetChecklists, titleVisibility: .visible) {
            if model.canResetAircraft {
                Button("Reiniciar todo y avión en Cold & Dark", role: .destructive) {
                    model.resetProcedures(model.procedures, aircraft: true)
                }
            }
            Button("Desmarcar todo lo marcado a mano", role: .destructive) { model.resetAllTicks() }
        } message: {
            Text("Los ítems detectados siguen a los mandos; en el modo demo puedes volver también el avión a Cold & Dark.")
        }
        .confirmationDialog("¿Reiniciar \(phaseToReset?.title ?? "la fase")?",
                            isPresented: Binding(get: { phaseToReset != nil }, set: { if !$0 { phaseToReset = nil } }),
                            titleVisibility: .visible, presenting: phaseToReset) { group in
            if model.canResetAircraft {
                Button("Reiniciar y avión en Cold & Dark", role: .destructive) {
                    model.resetProcedures(group.procedures, aircraft: true)
                }
            }
            Button("Desmarcar lo marcado a mano", role: .destructive) { model.resetTicks(ofPhase: group.id) }
        } message: { group in
            Text("\(group.procedures.count) procedimientos de esta fase.")
        }
        .confirmationDialog("¿Borrar todos los resultados de ejercicios?", isPresented: $confirmDeleteResults, titleVisibility: .visible) {
            Button("Borrar resultados", role: .destructive) { model.deleteResults(of: nil) }
        } message: {
            Text("Se pierden las estrellas y el historial de todos los ejercicios.")
        }
        // Opening a procedure from elsewhere (checklist column, turnaround) unfolds its phase.
        .onChange(of: model.activeProcedure?.phase) { _, phase in
            if let phase { expandedRaw = StoredIDs.toggled(expandedRaw, "flight:\(phase)", on: true) }
        }
    }

    // MARK: Vuelo

    /// Each phase: tapping it shows its panels, unfolding it lists its flows and checklists.
    @ViewBuilder
    private var flightTab: some View {
        let byPhase = proceduresByPhase
        Section {
            ForEach(model.layout.phases) { phase in
                if let group = byPhase[phase.id], !group.procedures.isEmpty {
                    DisclosureGroup(isExpanded: disclosureExpanded("flight:\(phase.id)")) {
                        procedureRows(group.procedures)
                    } label: {
                        phaseRow(phase, group: group)
                    }
                } else {
                    phaseRow(phase, group: nil)
                }
            }
            if let other = byPhase["other"], !other.procedures.isEmpty {
                DisclosureGroup(isExpanded: disclosureExpanded("flight:other")) {
                    procedureRows(other.procedures)
                } label: {
                    SidebarRow(title: "Otros", icon: "list.bullet")
                }
            }
        } header: {
            let done = model.procedures.filter { model.isComplete($0) }.count
            SectionHeader(title: "Fases de vuelo", detail: model.procedures.isEmpty ? nil : "\(done)/\(model.procedures.count)")
        } footer: {
            Text("Toca una fase para ver sus paneles; despliégala para sus procedimientos.")
        }
    }

    private func phaseRow(_ phase: FlightPhase, group: ProcedureStyle.PhaseGroup?) -> some View {
        let total = group?.procedures.count ?? 0
        let complete = group?.procedures.filter { model.isComplete($0) }.count ?? 0
        return SidebarRow(title: phase.title, icon: phase.icon ?? "airplane",
                          detail: total == 0 || complete == total ? nil : "\(complete)/\(total)",
                          done: total > 0 && complete == total)
            .tag(PanelSelection.phase(phase.id))
            .contextMenu {
                if let group {
                    Button("Reiniciar fase…", systemImage: "arrow.counterclockwise") { phaseToReset = group }
                }
                Button("Crear panel a partir de esta fase", systemImage: "square.on.square") {
                    editing = EditorTarget(panel: model.customPanel(fromPhase: phase.id))
                }
            }
    }

    private func procedureRows(_ procedures: [Procedure]) -> some View {
        ForEach(procedures) { procedure in
            ProcedureRow(procedure: procedure)
                .tag(PanelSelection.procedure(procedure.id))
                .contextMenu {
                    Button("Abrir en la columna", systemImage: "sidebar.right") {
                        model.open(procedure: procedure.id)
                    }
                    Button("Reiniciar", systemImage: "arrow.counterclockwise") {
                        model.resetTicks(of: procedure)
                    }
                }
        }
    }

    // MARK: Cabina

    @ViewBuilder
    private var cockpitTab: some View {
        Section {
            myPanels
        } header: {
            SectionHeader(title: "Mis paneles", detail: model.customPanels.isEmpty ? nil : "\(model.customPanels.count)")
        }
        Section {
            ForEach(groups) { group in
                let sections = model.sections(of: group.id)
                if sections.count > 1 {
                    DisclosureGroup(isExpanded: disclosureExpanded("zones:\(group.id)")) {
                        ForEach(sections) { panel in
                            Text(model.displayTitle(of: panel))
                                .font(.callout)
                                .lineLimit(1)
                                .tag(PanelSelection.subpanel(panel.id))
                        }
                    } label: {
                        SidebarRow(title: group.title, icon: group.icon ?? "square.grid.2x2", detail: "\(sections.count)")
                            .tag(PanelSelection.group(group.id))
                    }
                } else {
                    SidebarRow(title: group.title, icon: group.icon ?? "square.grid.2x2")
                        .tag(PanelSelection.group(group.id))
                }
            }
            .onMove { source, destination in
                var ids = groups.map(\.id)
                ids.move(fromOffsets: source, toOffset: destination)
                groupOrderRaw = StoredIDs.encode(ids)
            }
            SidebarRow(title: "Todos los paneles", icon: "rectangle.3.group")
                .tag(PanelSelection.all)
        } header: {
            SectionHeader(title: "Zonas de cabina", detail: nil)
        } footer: {
            Text("Toca una zona para verla entera; despliégala para ir a una sección.")
        }
    }

    @ViewBuilder
    private var myPanels: some View {
        ForEach(model.customPanels) { panel in
            SidebarRow(title: panel.title, icon: panel.icon, detail: "\(panel.items.count)")
                .tag(PanelSelection.custom(panel.id))
                .contextMenu { customPanelMenu(panel) }
                .swipeActions {
                    Button("Eliminar", role: .destructive) { model.deleteCustomPanel(panel.id) }
                    Button("Editar") { editing = EditorTarget(panel: panel) }.tint(.blue)
                }
        }
        .onMove { model.moveCustomPanels(from: $0, to: $1) }
        if !isEditing {
            Button {
                editing = EditorTarget(panel: nil)
            } label: {
                Label("Nuevo panel", systemImage: "plus.circle")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private func customPanelMenu(_ panel: CustomPanel) -> some View {
        Button("Editar", systemImage: "pencil") { editing = EditorTarget(panel: panel) }
        Button("Duplicar", systemImage: "plus.square.on.square") {
            var copy = panel
            copy.id = UUID().uuidString
            copy.title = panel.title + " (copia)"
            model.save(copy)
        }
        Button("Eliminar", systemImage: "trash", role: .destructive) {
            model.deleteCustomPanel(panel.id)
        }
    }

    // MARK: Práctica

    @ViewBuilder
    private var practiceTab: some View {
        @Bindable var model = model
        Section {
            Toggle(isOn: $model.learnMode) {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Modo aprender")
                        Text("Toca un mando para ver qué hace")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "graduationcap")
                }
            }
        } header: {
            SectionHeader(title: "Aprender", detail: nil)
        }
        Section {
            ExerciseList()
        } header: {
            let passed = model.exercises.filter { (model.bestResult(of: $0.id)?.stars ?? 0) > 0 }.count
            SectionHeader(title: "Ejercicios", detail: model.exercises.isEmpty ? nil : "\(passed)/\(model.exercises.count) ★")
        }
        Section {
            TurnaroundList()
        } header: {
            SectionHeader(title: "Turnaround", detail: model.flightLog.isEmpty ? nil : "\(model.flightLog.count) vuelos")
        }
    }

    // MARK: Expansion

    private func disclosureExpanded(_ key: String) -> Binding<Bool> {
        Binding(get: { StoredIDs.decode(expandedRaw).contains(key) },
                set: { open in expandedRaw = StoredIDs.toggled(expandedRaw, key, on: open) })
    }
}

// MARK: Rows

/// Icon, title and an optional trailing count or tick, the same in every section.
private struct SidebarRow: View {
    let title: String
    let icon: String
    var detail: String? = nil
    var done = false

    var body: some View {
        HStack(spacing: 10) {
            Label(title, systemImage: icon)
                .lineLimit(1)
            Spacer(minLength: 4)
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(PanelTheme.checklistGreen)
                    .imageScale(.small)
            } else if let detail {
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct ProcedureRow: View {
    let procedure: Procedure
    @Environment(PanelModel.self) private var model

    var body: some View {
        let progress = model.progress(of: procedure)
        HStack(spacing: 10) {
            Image(systemName: ProcedureStyle.icon(procedure.kind))
                .foregroundStyle(procedure.kind == .checklist ? PanelTheme.checklistCyan : .secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(procedure.title)
                    .font(procedure.kind == .checklist ? .callout.monospaced() : .callout)
                    .lineLimit(1)
                Text(ProcedureStyle.kindTitle(procedure.kind))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if progress.total > 0 && progress.done == progress.total {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(PanelTheme.checklistGreen)
            } else if progress.done > 0 {
                Text("\(progress.done)/\(progress.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// App identity and simulator status at the top of the sidebar.
private struct SidebarHeader: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image("Logo")
                .resizable()
                .interpolation(.high)
                .frame(width: 44, height: 44)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("ToLiss A320")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(model.statusColor)
                        .frame(width: 7, height: 7)
                    Text(model.status == .connected && !model.demoMode ? "X-Plane · \(model.host)" : model.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// Shortcut to the checklist column with the procedure in progress.
private struct ActiveChecklistRow: View {
    let procedure: Procedure
    @Environment(PanelModel.self) private var model

    var body: some View {
        let progress = model.progress(of: procedure)
        Button {
            model.showChecklist.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(model.showChecklist ? "Ocultar checklist" : "Checklist en curso",
                          systemImage: model.showChecklist ? "sidebar.right" : "checklist")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(PanelTheme.checklistCyan)
                    Spacer()
                    Text("\(progress.done)/\(progress.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(procedure.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .tint(progress.done == progress.total ? PanelTheme.checklistGreen : PanelTheme.checklistCyan)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

/// Flat list of everything whose name matches the search.
private struct SearchResults: View {
    let query: String
    @Environment(PanelModel.self) private var model

    private func matches(_ text: String) -> Bool {
        text.range(of: query.trimmingCharacters(in: .whitespaces), options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    var body: some View {
        let procedures = model.procedures.filter { matches($0.title) || $0.items.contains { matches($0.challenge) } }
        let custom = model.customPanels.filter { matches($0.title) }
        let phases = model.layout.phases.filter { matches($0.title) }
        let groups = model.layout.groups.filter { matches($0.title) }
        let sections = model.subpanels.filter { matches(model.displayTitle(of: $0)) }
        let exercises = model.exercises.filter { matches($0.title) || matches($0.summary ?? "") }
        if procedures.isEmpty && custom.isEmpty && phases.isEmpty && groups.isEmpty && sections.isEmpty && exercises.isEmpty {
            Section {
                Text("Sin resultados para «\(query)»")
                    .foregroundStyle(.secondary)
            }
        }
        if !procedures.isEmpty {
            Section("Procedimientos") {
                ForEach(procedures) { ProcedureRow(procedure: $0).tag(PanelSelection.procedure($0.id)) }
            }
        }
        if !custom.isEmpty || !phases.isEmpty || !groups.isEmpty {
            Section("Paneles") {
                ForEach(custom) { SidebarRow(title: $0.title, icon: $0.icon).tag(PanelSelection.custom($0.id)) }
                ForEach(phases) { SidebarRow(title: $0.title, icon: $0.icon ?? "airplane").tag(PanelSelection.phase($0.id)) }
                ForEach(groups) { SidebarRow(title: $0.title, icon: $0.icon ?? "square.grid.2x2").tag(PanelSelection.group($0.id)) }
            }
        }
        if !exercises.isEmpty {
            Section("Ejercicios") {
                ForEach(exercises) { exercise in
                    Button {
                        model.exerciseBriefingID = exercise.id
                    } label: {
                        SidebarRow(title: exercise.title, icon: "stopwatch", detail: exercise.level)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        if !sections.isEmpty {
            Section("Secciones") {
                ForEach(sections) { panel in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(model.displayTitle(of: panel))
                        Text(model.layout.groups.first { $0.id == panel.groupID }?.title ?? "")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .tag(PanelSelection.subpanel(panel.id))
                }
            }
        }
    }
}

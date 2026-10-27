import SwiftUI
import XPlaneKit

/// Sidebar sections in their default order. The user reorders and hides them from
/// "Personalizar barra lateral"; the choice lives in UserDefaults.
enum SidebarSection: String, CaseIterable, Identifiable {
    case myPanels
    case procedures
    case exercises
    case phases
    case cockpit
    case sections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .myPanels: return "Mis paneles"
        case .procedures: return "Procedimientos"
        case .exercises: return "Ejercicios"
        case .phases: return "Fases de vuelo"
        case .cockpit: return "Cabina"
        case .sections: return "Secciones"
        }
    }

    var icon: String {
        switch self {
        case .myPanels: return "square.grid.2x2"
        case .procedures: return "checklist"
        case .exercises: return "stopwatch"
        case .phases: return "airplane.departure"
        case .cockpit: return "rectangle.3.group"
        case .sections: return "square.split.2x2"
        }
    }
}

/// Comma-separated ids kept in @AppStorage (orders, hidden and expanded sets).
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

/// Left column: status, the user's panels, procedures, flight phases, cockpit areas and every
/// section, in collapsible sections the user can reorder, hide and search.
struct SidebarView: View {
    @Environment(PanelModel.self) private var model
    /// Panel being edited; nil panel means "new".
    @State private var editing: EditorTarget?
    @State private var query = ""
    @State private var editMode: EditMode = .inactive
    @State private var showOrganizer = false
    @State private var confirmResetChecklists = false
    @State private var confirmDeleteResults = false
    @State private var phaseToReset: ProcedureStyle.PhaseGroup?

    @AppStorage("sidebar.order") private var orderRaw = ""
    @AppStorage("sidebar.hidden") private var hiddenRaw = ""
    @AppStorage("sidebar.collapsed") private var collapsedRaw = ""
    /// Disclosure groups inside sections (procedure phases, section groups) start closed.
    @AppStorage("sidebar.expanded") private var expandedRaw = "procedures:cold_dark"
    @AppStorage("sidebar.phaseOrder") private var phaseOrderRaw = ""
    @AppStorage("sidebar.groupOrder") private var groupOrderRaw = ""

    private struct EditorTarget: Identifiable {
        let id = UUID()
        let panel: CustomPanel?
    }

    /// iOS only offers `List(selection:)` with an optional value; keep the last choice on deselect.
    private var selection: Binding<PanelSelection?> {
        Binding(get: { model.selection },
                set: { newValue in if let newValue { model.selection = newValue } })
    }

    private var visibleSections: [SidebarSection] {
        let hidden = Set(StoredIDs.decode(hiddenRaw))
        return StoredIDs.ordered(SidebarSection.allCases, by: orderRaw, id: \.rawValue)
            .filter { !hidden.contains($0.rawValue) }
    }

    private var phases: [FlightPhase] {
        StoredIDs.ordered(model.layout.phases, by: phaseOrderRaw, id: \.id)
    }

    private var groups: [PanelGroup] {
        StoredIDs.ordered(model.layout.groups, by: groupOrderRaw, id: \.id)
    }

    private var isEditing: Bool { editMode == .active }

    var body: some View {
        List(selection: selection) {
            Section {
                SidebarHeader()
                if let active = model.activeProcedure {
                    ActiveChecklistRow(procedure: active)
                }
            }
            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                ForEach(visibleSections) { section in
                    Section(isExpanded: sectionExpanded(section)) {
                        content(for: section)
                    } header: {
                        SectionHeader(title: section.title, detail: detail(for: section))
                    }
                }
            } else {
                SearchResults(query: query)
            }
        }
        .listStyle(.sidebar)
        .environment(\.editMode, $editMode)
        .searchable(text: $query, placement: .sidebar, prompt: "Buscar paneles y procedimientos")
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
                        Button("Ordenar elementos", systemImage: "arrow.up.arrow.down") {
                            withAnimation { editMode = .active }
                        }
                        Button("Personalizar barra lateral…", systemImage: "sidebar.left") { showOrganizer = true }
                        Divider()
                        Button("Nuevo panel", systemImage: "plus") { editing = EditorTarget(panel: nil) }
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
        .sheet(isPresented: $showOrganizer) {
            SidebarOrganizer()
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
    }

    // MARK: Sections

    @ViewBuilder
    private func content(for section: SidebarSection) -> some View {
        switch section {
        case .myPanels: myPanels
        case .procedures: procedures
        case .exercises: ExerciseList()
        case .phases: phaseRows
        case .cockpit: cockpit
        case .sections: sectionGroups
        }
    }

    private func detail(for section: SidebarSection) -> String? {
        switch section {
        case .myPanels:
            return model.customPanels.isEmpty ? nil : "\(model.customPanels.count)"
        case .procedures:
            let done = model.procedures.filter { model.isComplete($0) }.count
            return model.procedures.isEmpty ? nil : "\(done)/\(model.procedures.count)"
        case .exercises:
            let passed = model.exercises.filter { (model.bestResult(of: $0.id)?.stars ?? 0) > 0 }.count
            return model.exercises.isEmpty ? nil : "\(passed)/\(model.exercises.count)"
        case .phases:
            return "\(model.layout.phases.count)"
        case .cockpit:
            return nil
        case .sections:
            return "\(model.subpanels.count)"
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

    @ViewBuilder
    private var procedures: some View {
        if model.procedures.isEmpty {
            Text("Sin procedimientos en mapping/procedures.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        ForEach(ProcedureStyle.groups(model.procedures, phases: model.layout.phases)) { group in
            DisclosureGroup(isExpanded: disclosureExpanded("procedures:\(group.id)")) {
                ForEach(group.procedures) { procedure in
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
            } label: {
                let complete = group.procedures.filter { model.isComplete($0) }.count
                SidebarRow(title: group.title, icon: group.icon,
                           detail: complete == group.procedures.count ? nil : "\(complete)/\(group.procedures.count)",
                           done: complete == group.procedures.count)
                    .contextMenu {
                        Button("Reiniciar fase…", systemImage: "arrow.counterclockwise") { phaseToReset = group }
                    }
            }
        }
    }

    @ViewBuilder
    private var phaseRows: some View {
        ForEach(phases) { phase in
            SidebarRow(title: phase.title, icon: phase.icon ?? "airplane", detail: "\(phase.subpanels.count)")
                .tag(PanelSelection.phase(phase.id))
                .contextMenu {
                    Button("Crear panel a partir de esta fase", systemImage: "square.on.square") {
                        editing = EditorTarget(panel: model.customPanel(fromPhase: phase.id))
                    }
                }
        }
        .onMove { source, destination in
            var ids = phases.map(\.id)
            ids.move(fromOffsets: source, toOffset: destination)
            phaseOrderRaw = StoredIDs.encode(ids)
        }
    }

    @ViewBuilder
    private var cockpit: some View {
        ForEach(groups) { group in
            SidebarRow(title: group.title, icon: group.icon ?? "square.grid.2x2")
                .tag(PanelSelection.group(group.id))
        }
        .onMove { source, destination in
            var ids = groups.map(\.id)
            ids.move(fromOffsets: source, toOffset: destination)
            groupOrderRaw = StoredIDs.encode(ids)
        }
        SidebarRow(title: "Todos los paneles", icon: "rectangle.3.group")
            .tag(PanelSelection.all)
    }

    @ViewBuilder
    private var sectionGroups: some View {
        ForEach(groups) { group in
            let sections = model.sections(of: group.id)
            if !sections.isEmpty {
                DisclosureGroup(isExpanded: disclosureExpanded("sections:\(group.id)")) {
                    ForEach(sections) { panel in
                        Text(model.displayTitle(of: panel))
                            .font(.callout)
                            .lineLimit(1)
                            .tag(PanelSelection.subpanel(panel.id))
                    }
                } label: {
                    SidebarRow(title: group.title, icon: group.icon ?? "square.grid.2x2", detail: "\(sections.count)")
                }
            }
        }
    }

    // MARK: Expansion

    private func sectionExpanded(_ section: SidebarSection) -> Binding<Bool> {
        Binding(get: { !StoredIDs.decode(collapsedRaw).contains(section.rawValue) },
                set: { open in collapsedRaw = StoredIDs.toggled(collapsedRaw, section.rawValue, on: !open) })
    }

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
        if procedures.isEmpty && custom.isEmpty && phases.isEmpty && groups.isEmpty && sections.isEmpty {
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

// MARK: Organizer

/// Reorder and show or hide the sidebar sections.
private struct SidebarOrganizer: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("sidebar.order") private var orderRaw = ""
    @AppStorage("sidebar.hidden") private var hiddenRaw = ""
    @AppStorage("sidebar.phaseOrder") private var phaseOrderRaw = ""
    @AppStorage("sidebar.groupOrder") private var groupOrderRaw = ""

    private var sections: [SidebarSection] {
        StoredIDs.ordered(SidebarSection.allCases, by: orderRaw, id: \.rawValue)
    }

    private func visible(_ section: SidebarSection) -> Binding<Bool> {
        Binding(get: { !StoredIDs.decode(hiddenRaw).contains(section.rawValue) },
                set: { show in hiddenRaw = StoredIDs.toggled(hiddenRaw, section.rawValue, on: !show) })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(sections) { section in
                        Toggle(isOn: visible(section)) {
                            Label(section.title, systemImage: section.icon)
                        }
                    }
                    .onMove { source, destination in
                        var ids = sections.map(\.rawValue)
                        ids.move(fromOffsets: source, toOffset: destination)
                        orderRaw = StoredIDs.encode(ids)
                    }
                } header: {
                    Text("Secciones")
                } footer: {
                    Text("Arrastra para cambiar el orden. Las secciones ocultas siguen disponibles en la búsqueda.")
                }
                Section {
                    Button("Restablecer orden y visibilidad") {
                        orderRaw = ""
                        hiddenRaw = ""
                        phaseOrderRaw = ""
                        groupOrderRaw = ""
                    }
                } footer: {
                    Text("El orden de fases y zonas de cabina se cambia con «Ordenar elementos» en la barra lateral.")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Barra lateral")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}

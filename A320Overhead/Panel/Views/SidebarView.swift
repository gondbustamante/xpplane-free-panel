import SwiftUI
import XPlaneKit

/// Left column: flight phases (subpanels from any group) and panel groups (overhead, pedestal…).
struct SidebarView: View {
    @Environment(PanelModel.self) private var model
    /// Panel being edited; a fresh `CustomPanel` (not yet in the model) means "new".
    @State private var editing: EditorTarget?

    private struct EditorTarget: Identifiable {
        let id = UUID()
        let panel: CustomPanel?
    }

    /// iOS only offers `List(selection:)` with an optional value; keep the last choice on deselect.
    private var selection: Binding<PanelSelection?> {
        Binding(get: { model.selection },
                set: { newValue in if let newValue { model.selection = newValue } })
    }

    var body: some View {
        List(selection: selection) {
            Section {
                ForEach(model.customPanels) { panel in
                    Label(panel.title, systemImage: panel.icon)
                        .tag(PanelSelection.custom(panel.id))
                        .contextMenu {
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
                        .swipeActions {
                            Button("Editar") { editing = EditorTarget(panel: panel) }.tint(.blue)
                        }
                }
                .onMove { model.moveCustomPanels(from: $0, to: $1) }
                Button {
                    editing = EditorTarget(panel: nil)
                } label: {
                    Label("Nuevo panel", systemImage: "plus")
                }
            } header: {
                Text("Mis paneles")
            }
            if !model.layout.phases.isEmpty {
                Section("Fases de vuelo") {
                    ForEach(model.layout.phases) { phase in
                        Label(phase.title, systemImage: phase.icon ?? "airplane")
                            .tag(PanelSelection.phase(phase.id))
                            .contextMenu {
                                Button("Crear panel a partir de esta fase", systemImage: "square.on.square") {
                                    editing = EditorTarget(panel: model.customPanel(fromPhase: phase.id))
                                }
                            }
                    }
                }
            }
            Section("Paneles") {
                ForEach(model.layout.groups) { group in
                    Label(group.title, systemImage: group.icon ?? "square.grid.2x2")
                        .tag(PanelSelection.group(group.id))
                }
                Label("Todos", systemImage: "rectangle.3.group")
                    .tag(PanelSelection.all)
            }
            ForEach(model.layout.groups) { group in
                let sections = model.sections(of: group.id)
                if !sections.isEmpty {
                    Section("Secciones · \(group.title)") {
                        ForEach(sections) { panel in
                            Text(panel.title.isEmpty ? panel.id.replacingOccurrences(of: "_", with: " ").uppercased() : panel.title)
                                .font(.callout)
                                .tag(PanelSelection.subpanel(panel.id))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("A320")
        .toolbar {
            if model.selection.isCustom, let panel = model.selectedCustomPanel {
                ToolbarItem(placement: .primaryAction) {
                    Button("Editar", systemImage: "slider.horizontal.3") { editing = EditorTarget(panel: panel) }
                }
            }
        }
        .sheet(item: $editing) { target in
            CustomPanelEditor(panel: target.panel)
        }
    }
}

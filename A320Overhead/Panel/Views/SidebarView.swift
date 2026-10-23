import SwiftUI
import XPlaneKit

/// Left column: flight phases (subpanels from any group) and panel groups (overhead, pedestal…).
struct SidebarView: View {
    @Environment(PanelModel.self) private var model

    /// iOS only offers `List(selection:)` with an optional value; keep the last choice on deselect.
    private var selection: Binding<PanelSelection?> {
        Binding(get: { model.selection },
                set: { newValue in if let newValue { model.selection = newValue } })
    }

    var body: some View {
        List(selection: selection) {
            if !model.layout.phases.isEmpty {
                Section("Fases de vuelo") {
                    ForEach(model.layout.phases) { phase in
                        Label(phase.title, systemImage: phase.icon ?? "airplane")
                            .tag(PanelSelection.phase(phase.id))
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
    }
}

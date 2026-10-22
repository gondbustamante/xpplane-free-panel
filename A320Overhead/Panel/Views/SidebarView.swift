import SwiftUI
import XPlaneKit

/// Left column: flight phases (subpanels from any group) and panel groups (overhead, pedestal…).
struct SidebarView: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.selection) {
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
        }
        .listStyle(.sidebar)
        .navigationTitle("A320")
    }
}

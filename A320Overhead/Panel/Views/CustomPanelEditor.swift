import SwiftUI

/// Create or edit a custom panel: name, icon, items per row, and which sections go in, in order.
struct CustomPanelEditor: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CustomPanel
    @State private var confirmDelete = false

    /// New until saved: also covers a panel seeded from a flight phase.
    private var isNew: Bool { !model.isSaved(draft) }

    private static let icons = ["square.grid.2x2", "star", "bolt", "airplane", "airplane.departure",
                                "airplane.arrival", "flame", "fuelpump", "lightbulb", "gauge",
                                "keyboard", "slider.horizontal.3", "exclamationmark.triangle", "moon.zzz"]

    init(panel: CustomPanel?) {
        _draft = State(initialValue: panel ?? CustomPanel(title: ""))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Panel") {
                    TextField("Nombre, p. ej. Arranque", text: $draft.title)
                    Stepper("Elementos por fila: \(draft.columns)", value: $draft.columns, in: 1...4)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Self.icons, id: \.self) { icon in
                                Button {
                                    draft.icon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.title3)
                                        .frame(width: 40, height: 40)
                                        .background(RoundedRectangle(cornerRadius: 8)
                                            .fill(draft.icon == icon ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    if draft.items.isEmpty {
                        Text("Añade elementos desde la lista de abajo.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(draft.items, id: \.self) { item in
                        Label(model.title(ofItem: item), systemImage: "line.3.horizontal")
                    }
                    .onMove { draft.items.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { draft.items.remove(atOffsets: $0) }
                } header: {
                    Text("En este panel (\(draft.items.count))")
                } footer: {
                    Text("Arrastra para ordenar y desliza para quitar. Se dibujan de izquierda a derecha y de arriba abajo.")
                }

                ForEach(model.customPanelCatalog) { group in
                    Section("Añadir · \(group.title)") {
                        ForEach(group.items) { item in
                            let added = draft.items.contains(item.id)
                            Button {
                                if added {
                                    draft.items.removeAll { $0 == item.id }
                                } else {
                                    draft.items.append(item.id)
                                }
                            } label: {
                                HStack {
                                    Text(item.title).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                        .foregroundStyle(added ? Color.green : Color.accentColor)
                                }
                            }
                        }
                    }
                }

                if !isNew {
                    Section {
                        Button("Eliminar panel", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(isNew ? "Nuevo panel" : "Editar panel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        model.save(draft)
                        dismiss()
                    }
                    .disabled(draft.items.isEmpty)
                }
            }
            .confirmationDialog("¿Eliminar «\(draft.title)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    model.deleteCustomPanel(draft.id)
                    dismiss()
                }
            }
        }
    }
}

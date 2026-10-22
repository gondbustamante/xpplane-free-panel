import SwiftUI

struct ConnectionSettingsView: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = ""

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("X-Plane") {
                    TextField("IP del PC con X-Plane", text: $host)
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Puerto", text: $port)
                        .keyboardType(.numberPad)
                    Text("Ejecuta tools/xp_relay.py en el PC. Por defecto escucha en el puerto 8087 y reenvía a la Web API de X-Plane (8086), que solo acepta conexiones locales.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Interfaz") {
                    Toggle("Marcar controles con mapeo sin verificar", isOn: $model.showVerificationBadges)
                }
                if !model.unresolved.isEmpty {
                    Section("Datarefs no reconocidos por el simulador") {
                        ForEach(model.unresolved.sorted(), id: \.self) { name in
                            Text(name).font(.footnote.monospaced())
                        }
                        Text("Normalmente significa que el ToLiss no está cargado o que el nombre cambió en esta versión.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if let error = model.lastError {
                    Section("Último error") {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Conexión")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar y conectar") {
                        model.host = host.trimmingCharacters(in: .whitespacesAndNewlines)
                        if let value = Int(port), (1...65535).contains(value) { model.port = value }
                        model.connect()
                        dismiss()
                    }
                }
            }
            .onAppear {
                host = model.host
                port = String(model.port)
            }
        }
    }
}

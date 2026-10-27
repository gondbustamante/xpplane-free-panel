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
                Section {
                    Toggle("Modo demo", isOn: $model.demoMode)
                } footer: {
                    Text("Simula el avión en el iPad, sin X-Plane ni red: los interruptores, el FCU, las radios y el MCDU responden como si hubiera simulador. Empieza siempre en Cold & Dark al conectar.")
                }
                Section {
                    Picker("Tiempos", selection: $model.demoTiming) {
                        ForEach(DemoTiming.allCases) { timing in
                            Text(timing.title).tag(timing)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Sistemas del modo demo")
                } footer: {
                    Text(model.demoTiming.explanation)
                }
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
                Section {
                    Picker("Retroiluminación", selection: $model.backlightMode) {
                        ForEach(BacklightMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    if model.backlightMode != .off {
                        HStack {
                            Image(systemName: "sun.min")
                            Slider(value: $model.backlightManualLevel, in: 0.1...1)
                            Image(systemName: "sun.max")
                        }
                    }
                } header: {
                    Text("Retroiluminación")
                } footer: {
                    Text("«Según el avión» sigue los mandos de iluminación integral de la cabina (OVHD INTEG LT, panel principal, FCU y MCDU). El nivel manual se usa en «Siempre» y mientras no hay conexión.")
                }
                Section("Interfaz") {
                    Toggle("Marcar controles con mapeo sin verificar", isOn: $model.showVerificationBadges)
                    Text("Útil al verificar datarefs desde Diagnóstico. Apagado por defecto para que el panel se vea como el del avión.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                    Button(model.demoMode ? "Iniciar demo" : "Guardar y conectar") {
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

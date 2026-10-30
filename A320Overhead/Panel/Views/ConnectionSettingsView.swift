import SwiftUI
import XPlaneKit

struct ConnectionSettingsView: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var host = ""
    @State private var port = ""
    @State private var showDiagnostics = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 10) {
                        Circle().fill(model.statusColor).frame(width: 10, height: 10)
                        Text(model.statusLabel).lineLimit(2)
                        Spacer()
                        Button(model.status.isActive ? "Desconectar" : "Conectar", action: toggleConnection)
                            .buttonStyle(.borderedProminent)
                            .tint(model.status.isActive ? .red : nil)
                    }
                    Picker("Origen", selection: $model.demoMode) {
                        Text("X-Plane").tag(false)
                        Text("Modo demo").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if model.demoMode {
                        Picker("Tiempos", selection: $model.demoTiming) {
                            ForEach(DemoTiming.allCases) { timing in
                                Text(timing.title).tag(timing)
                            }
                        }
                    } else {
                        LabeledContent("IP del PC") {
                            TextField("192.168.1.10", text: $host)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numbersAndPunctuation)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        LabeledContent("Puerto") {
                            TextField("8087", text: $port)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.numberPad)
                        }
                    }
                } header: {
                    Text("Conexión")
                } footer: {
                    if model.demoMode {
                        Text("Simula el avión en el iPad, sin X-Plane ni red: los interruptores, el FCU, las radios y el MCDU responden como si hubiera simulador. Empieza siempre en Cold & Dark al conectar. \(model.demoTiming.explanation)")
                    } else {
                        Text("Ejecuta tools/xp_relay.py en el PC. Por defecto escucha en el puerto 8087 y reenvía a la Web API de X-Plane (8086), que solo acepta conexiones locales.")
                    }
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
                Section("Avanzado") {
                    Button("Diagnóstico de datarefs…", systemImage: "stethoscope") { showDiagnostics = true }
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
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") {
                        applyAddress()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
            }
            .onAppear {
                host = model.host
                port = String(model.port)
            }
        }
    }

    private func toggleConnection() {
        if model.status.isActive {
            model.disconnect()
        } else {
            applyAddress()
            model.connect()
        }
    }

    /// Saves the typed address; reconnects if it changed while connected to X-Plane.
    private func applyAddress() {
        let newHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let newPort = Int(port).flatMap { (1...65535).contains($0) ? $0 : nil } ?? model.port
        guard newHost != model.host || newPort != model.port else { return }
        if !newHost.isEmpty { model.host = newHost }
        model.port = newPort
        if model.status.isActive && !model.demoMode { model.connect() }
    }
}

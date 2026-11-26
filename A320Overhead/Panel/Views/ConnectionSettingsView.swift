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
                    Picker("Avión", selection: Binding(get: { model.aircraft }, set: { model.selectAircraft($0) })) {
                        ForEach(AircraftProfile.all) { profile in
                            Text(profile.product).tag(profile)
                        }
                    }
                    .pickerStyle(.segmented)
                    if let detected = model.detectedAircraftMismatch {
                        Button("X-Plane tiene cargado un \(model.simAircraftICAO ?? detected.icaoType): usar \(detected.product)") {
                            model.selectAircraft(detected)
                        }
                    }
                } header: {
                    Text("Avión")
                } footer: {
                    Text("Elige el avión que vuelas en X-Plane. Paneles, procedimientos, guía, ejercicios, turnaround y la simulación del modo demo se adaptan a él; al cambiarlo la app se reconecta. El A340 comparte con el A320 el FCU, el EFIS, las radios y el MCDU, y tiene su propio overhead de cuatro motores: sus mandos nuevos están sin verificar contra tu ToLiss A340 (Diagnóstico de datarefs).")
                }
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
                        Text("En el PC de X-Plane abre el enlace: XPRelay.exe en Windows (doble clic, sin instalar nada) o tools/xp_relay.py con Python. Escucha en el puerto 8087 y reenvía a la Web API de X-Plane (8086), que solo acepta conexiones locales. La ventana del enlace muestra la IP que hay que poner aquí.")
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
                Section {
                    TextField("Usuario de SimBrief o Pilot ID", text: $model.simBriefUser)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("SimBrief")
                } footer: {
                    Text("Para cargar tu último OFP en la Guía MCDU y en el turnaround. El Pilot ID está en SimBrief → Account Settings.")
                }
                Section {
                    Toggle("After landing al salir de la pista", isOn: $model.autoAfterLanding)
                    Toggle("Incluir arranque del APU", isOn: $model.afterLandingAPU)
                        .disabled(!model.autoAfterLanding)
                    Toggle("Ascenso y descenso al cruzar FL100", isOn: $model.autoFL100)
                    Toggle("Parking al parar los motores", isOn: $model.autoParking)
                } header: {
                    Text("Automatización")
                } footer: {
                    Text("Con X-Plane. After landing al girar fuera de la pista: ground spoilers, flaps 0, strobe, luces de aterrizaje y de rodaje, TCAS y modo de motor. FL100 subiendo: luces de aterrizaje recogidas; bajando: luces de aterrizaje y cinturones. Parking cuando tú cortas los motores con el freno puesto: cinturones, beacon, luces, bombas de combustible, transpondedor y, con el APU en marcha, su sangrado. Cualquier flujo se puede ejecutar también con «Ejecutar flujo» en el checklist. Nunca durante un examen.")
                }
                Section {
                    Toggle("Copiloto por voz", isOn: $model.voiceCopilotEnabled)
                    Picker("Idioma de las órdenes", selection: $model.voiceCopilotLanguage) {
                        Text("Inglés").tag("en-US")
                        Text("Español").tag("es-ES")
                    }
                    .disabled(!model.voiceCopilotEnabled)
                } header: {
                    Text("Copiloto por voz")
                } footer: {
                    Text("Toca el micrófono de la barra y di la orden; el copiloto la ejecuta y la repite. «gear up/down», «flaps one/two/three/full/up», «landing lights on/off/retract», «nose light taxi/takeoff/off», «strobe on/auto/off», «beacon», «seat belts», «arm/disarm spoilers», «autopilot one/two», «autothrust», «APU start/off», «APU bleed», «TCAS TA RA», «engine/wing anti ice», «ignition», y flujos: «after takeoff», «after landing», «after start», «before start», «line up», «parking», «climb/descent flow». En español también: «tren arriba», «flaps uno», «luces de aterrizaje encendidas»…")
                }
                Section {
                    Toggle("Anuncios de cabina", isOn: $model.cabinAnnouncements)
                } header: {
                    Text("Cabina")
                } footer: {
                    Text("Con X-Plane: bienvenida al encender el beacon, CABIN SECURE en el rodaje y antes del aterrizaje, «seats for take-off» al encender los strobes, cinturones apagados, anuncio del comandante en crucero, descenso, llegada y desembarque al apagar el beacon.")
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

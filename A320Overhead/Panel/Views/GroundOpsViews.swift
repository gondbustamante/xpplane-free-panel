import SwiftUI
import XPlaneKit

// Ground and departure, from the dispatch sheet: pushback and start phraseology (3.2), taxi
// with single-engine option (3.3), de-icing with holdover (3.4) and the line-up check with a
// stop-and-check when the runway changes (3.5).

// MARK: 3.2 Pushback and start

struct PushbackView: View {
    private struct Line: Identifiable {
        let id = UUID()
        let who: String
        let text: String
        let note: String?
    }

    private let lines: [Line] = [
        Line(who: "Cabina", text: "Ground from flight deck, ready for pushback, brakes set.",
             note: "Antes: puertas cerradas, toboganes armados, ATC concede push y la baliza (BEACON) encendida."),
        Line(who: "Tierra", text: "Flight deck from ground, tow bar connected, pin inserted, cleared to release brakes."),
        Line(who: "Cabina", text: "Brakes released. Push facing west, cleared to start engines.",
             note: "La dirección y el permiso de arranque los da ATC (\"pushback approved, facing…\")."),
        Line(who: "Tierra", text: "Pushing back. Cleared to start engine two.",
             note: "En el A320 se arranca primero el motor 2: su bomba amarilla da presión a los frenos del aparcamiento."),
        Line(who: "Cabina", text: "Starting engine two.", note: "ENG MODE IGN/START, ENG 2 MASTER ON. Vigila N2, EGT y FF."),
        Line(who: "Tierra", text: "Pushback complete, set parking brake.", note: nil),
        Line(who: "Cabina", text: "Parking brake set. Cleared to disconnect.", note: nil),
        Line(who: "Tierra", text: "Disconnecting. Pin and tow bar will be shown on your left. Bye bye.",
             note: "Busca al operario con el pasador en la mano antes de rodar: es la confirmación de que el tractor está desconectado."),
    ]

    var body: some View {
        List {
            Section {
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.who.uppercased()).font(.caption2.weight(.bold))
                            .foregroundStyle(line.who == "Cabina" ? PanelTheme.checklistCyan : PanelTheme.checklistGreen)
                        Text(line.text).font(.callout.monospaced())
                        if let note = line.note {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text("Interfono con el personal de tierra")
            } footer: {
                Text("Fraseología habitual en inglés. Cada aerolínea tiene la suya; lo importante es no soltar frenos sin permiso de tierra y no rodar sin ver el pasador.")
            }
            Section("Si algo va mal") {
                Text("«Stop pushback» (o «Stop, stop, stop»): tierra detiene el tractor. Freno de aparcamiento solo cuando tierra lo pida, o romperás la barra.")
                    .font(.footnote)
                Text("Fuego o fallo en el arranque: «Ground, engine fire/start fault engine two, stand clear» y procedimiento de la QRH.")
                    .font(.footnote)
            }
        }
        .navigationTitle("Pushback y arranque")
    }
}

// MARK: 3.3 Taxi

struct TaxiView: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        let taxiMinutes = model.turnaround?.plan.taxi ?? model.ofp?.taxiOutMinutes ?? 10
        Form {
            Section {
                LabeledContent("Rodaje previsto", value: "\(Int(taxiMinutes)) min")
                if let fuel = model.ofp.flatMap({ $0.kilograms($0.fuel.taxi) }) {
                    LabeledContent("Combustible de rodaje (OFP)", value: "\(Int(fuel)) kg")
                }
                if let run = model.turnaround, let out = run.blockTimes.outTime {
                    let end = run.blockTimes.offTime ?? Date()
                    LabeledContent(run.blockTimes.offTime == nil ? "Rodando" : "Rodaje real",
                                   value: "\(Int((end.timeIntervalSince(out) / 60).rounded())) min")
                    if let atOut = run.fuelAtOut, let atOff = run.fuelAtOff {
                        LabeledContent("Combustible gastado", value: "\(Int(atOut - atOff)) kg")
                    }
                }
            } header: {
                Text("Rodaje de salida")
            } footer: {
                Text("El A320 gasta unos 10-12 kg por minuto en rodaje con los dos motores. Si el rodaje real se alarga mucho, puede comerse la contingencia: compruébalo en FUEL PRED antes de despegar.")
            }
            Section {
                Toggle("Rodar con un motor", isOn: Binding(get: { model.dispatch.singleEngineTaxi ?? false },
                                                         set: { on in model.updateDispatch { $0.singleEngineTaxi = on } }))
                if model.dispatch.singleEngineTaxi == true {
                    LabeledContent("Ahorro estimado", value: "\(Int(Taxi.singleEngineSaving(minutes: taxiMinutes))) kg")
                    if let takeoff = model.expectedTakeoff {
                        LabeledContent("Despegue previsto", value: TurnaroundFormat.local(takeoff))
                        LabeledContent("Arrancar el motor 1", value: TurnaroundFormat.local(Taxi.secondEngineStart(takeoff: takeoff)))
                    }
                }
            } header: {
                Text("Un solo motor")
            } footer: {
                Text("Muchas aerolíneas ruedan con el motor 2 y arrancan el 1 durante el rodaje, con tiempo para unos \(Int(Taxi.warmUpMinutes)) minutos de calentamiento antes del empuje de despegue. Ojo: con un motor el rodaje necesita más empuje (cuidado con el chorro en virajes cerrados y rampas), la APU sigue dando el bleed y el hidráulico verde llega por la PTU. No se usa con pista contaminada, pendiente o poco tiempo de rodaje. La app avisa (sin botones) cuando toca arrancar el segundo motor, con el turnaround en marcha.")
            }
        }
        .navigationTitle("Rodaje")
    }
}

// MARK: 3.4 De-icing

struct DeicingView: View {
    @Environment(PanelModel.self) private var model
    @State private var fluid: Deicing.Fluid = .typeIV
    @State private var condition: Deicing.Condition = .lightSnow
    @State private var temperature = -2

    var body: some View {
        Form {
            if let record = model.dispatch.deicing {
                Section {
                    LabeledContent("Líquido", value: record.fluid.title)
                    LabeledContent("Condición", value: "\(record.condition.title) · \(record.temperature) °C")
                    LabeledContent("Inicio del paso final", value: TurnaroundFormat.local(record.start))
                    if let holdover = record.holdover {
                        LabeledContent("Tiempo de protección", value: holdover.lowerBound == holdover.upperBound
                                       ? "\(holdover.upperBound) min" : "\(holdover.lowerBound)-\(holdover.upperBound) min")
                        TimelineView(.periodic(from: .now, by: 15)) { context in
                            let left = Deicing.remaining(start: record.start, holdover: holdover, at: context.date)
                            if left.toMaximum <= 0 {
                                Label("Protección agotada: hay que deshelar otra vez", systemImage: "xmark.octagon.fill")
                                    .foregroundStyle(.red)
                            } else if left.toMinimum <= 0 {
                                Label("Pasado el mínimo: quedan como mucho \(left.toMaximum) min. Inspección de contaminación antes de despegar",
                                      systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(PanelTheme.checklistAmber)
                            } else {
                                Label("Protegido al menos \(left.toMinimum) min más (hasta \(left.toMaximum))", systemImage: "checkmark.shield")
                                    .foregroundStyle(PanelTheme.checklistGreen)
                            }
                        }
                        if let takeoff = model.expectedTakeoff {
                            let at = Deicing.remaining(start: record.start, holdover: holdover, at: takeoff)
                            LabeledContent("Al despegue previsto (\(TurnaroundFormat.local(takeoff)))",
                                           value: at.toMaximum <= 0 ? "fuera de protección" : (at.toMinimum <= 0 ? "pasado el mínimo" : "protegido"))
                        }
                    } else {
                        Label("Este líquido no protege a esa temperatura", systemImage: "xmark.octagon")
                            .foregroundStyle(PanelTheme.checklistAmber)
                    }
                    Button("Borrar el deshielo", role: .destructive) { model.updateDispatch { $0.deicing = nil } }
                } header: {
                    Text("Deshielo en curso")
                } footer: {
                    Text("El tiempo cuenta desde el inicio del último paso (el antihielo). Comunica a ATC y a cabina; el código de deshielo que te da el operario (tipo de líquido, concentración, hora de inicio) va al parte técnico.")
                }
            } else {
                Section {
                    Picker("Condición", selection: $condition) {
                        ForEach(Deicing.Condition.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    Stepper("Temperatura: \(temperature) °C", value: $temperature, in: -30...5)
                    Picker("Líquido final", selection: $fluid) {
                        ForEach(Deicing.Fluid.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    if let holdover = Deicing.holdover(fluid: fluid, condition: condition, temperature: temperature) {
                        LabeledContent("Tiempo de protección", value: holdover.lowerBound == holdover.upperBound
                                       ? "\(holdover.upperBound) min" : "\(holdover.lowerBound)-\(holdover.upperBound) min")
                    } else {
                        Text("Sin protección con este líquido a esa temperatura.").foregroundStyle(PanelTheme.checklistAmber)
                    }
                    Button {
                        let record = DeicingRecord(fluid: fluid, condition: condition, temperature: temperature, start: Date())
                        model.updateDispatch { $0.deicing = record }
                    } label: {
                        Label("Empieza el paso final ahora", systemImage: "timer")
                    }
                } header: {
                    Text("Planificar el deshielo")
                } footer: {
                    Text("Tiempos orientativos para entrenar, simplificados de las tablas genéricas. En la realidad se usan las tablas de la temporada (FAA/Transport Canada) para la marca exacta de líquido. Con el avión deshelado: APU bleed y packs apagados durante la aplicación, y motores en ralentí si están en marcha.")
                }
            }
        }
        .navigationTitle("Deshielo")
    }
}

// MARK: 3.5 Line-up

struct LineupView: View {
    @Environment(PanelModel.self) private var model

    static let items: [(id: String, text: String)] = [
        ("config", "T.O CONFIG en verde (prueba de configuración en el ECAM)"),
        ("runway", "Pista correcta: rumbo del PFD y del ND con la pista, posición en el ND en el umbral"),
        ("fma", "FMA y velocidades: V1, VR, V2 y FLEX/TOGA como en el briefing"),
        ("cabin", "Cabina avisada (\"Cabin crew, take your seats\") y señal de cinturones"),
        ("lights", "Luces de pista: STROBE ON, LAND ON, NOSE T.O, RWY TURN OFF ON"),
        ("tcas", "Transpondedor y TCAS en TA/RA, radar meteorológico y PWS"),
        ("packs", "Packs según el briefing (OFF si el rendimiento lo pide) y APU bleed"),
        ("clear", "Final libre (mira la aproximación) y autorización de despegue colacionada"),
    ]

    static func runwayChanged(ofp: SimBriefOFP, clearance: DepartureClearance) -> Bool {
        guard let planned = ofp.takeoff?.runway ?? ofp.origin.runway, !clearance.runway.isEmpty else { return false }
        return clearance.runway.uppercased() != planned.uppercased()
    }

    var body: some View {
        let done = model.dispatch.lineupDone ?? []
        Form {
            if let ofp = model.ofp, Self.runwayChanged(ofp: ofp, clearance: model.dispatch.clearance) {
                Section {
                    ForEach(Array([
                        "PARA: no ruedes hacia la pista nueva sin haber hecho esto. El cambio de pista es una de las amenazas clásicas.",
                        "Rendimiento: recalcula V1, VR, V2 y FLEX para la pista \(model.dispatch.clearance.runway) (TLR de SimBrief o tu calculadora).",
                        "MCDU: la pista y la SID nuevas en el F-PLN (o activa el SEC F-PLN si la preparaste). Revisa discontinuidades.",
                        "PERF TAKE OFF: velocidades, FLEX, flaps y THR RED/ACC nuevos.",
                        "FCU: altitud inicial de la nueva SID.",
                        "Briefing corto de la nueva salida (SID, altitud, fallo de motor) entre los dos pilotos.",
                    ].enumerated()), id: \.offset) { _, step in
                        Label(step, systemImage: "hand.raised")
                            .font(.footnote)
                    }
                } header: {
                    Text("Cambio de pista: \(ofp.takeoff?.runway ?? ofp.origin.runway ?? "") → \(model.dispatch.clearance.runway)")
                        .foregroundStyle(PanelTheme.checklistAmber)
                }
            }
            Section {
                ForEach(Self.items, id: \.id) { item in
                    let checked = done.contains(item.id)
                    Button {
                        model.updateDispatch { state in
                            var list = state.lineupDone ?? []
                            if checked { list.removeAll { $0 == item.id } } else { list.append(item.id) }
                            state.lineupDone = list
                        }
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(checked ? PanelTheme.checklistGreen : .secondary)
                            Text(item.text).foregroundStyle(checked ? .secondary : .primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Antes de entrar en pista")
            } footer: {
                Text("El último repaso antes de la pista activa (en muchas aerolíneas, la parte «below the line» de la lista BEFORE TAKEOFF).")
            }
        }
        .navigationTitle("Entrada en pista")
    }
}

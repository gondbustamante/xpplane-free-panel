import SwiftUI
import XPlaneKit

/// Dispatch and departure briefing for the loaded OFP, in the order the crew works at the
/// gate: flight summary and weights, fuel decision, weather, NOTAMs, MEL, duty period and the
/// plan itself; then ATIS, clearance, departure briefing (with SID constraints) and walkaround.
struct DispatchSheet: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let ofp = model.ofp {
                    home(ofp)
                } else {
                    ContentUnavailableView("Sin OFP", systemImage: "doc.text.magnifyingglass",
                                           description: Text("Carga tu plan de SimBrief en Vuelo → Plan de vuelo."))
                }
            }
            .navigationTitle("Despacho y briefing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func home(_ ofp: SimBriefOFP) -> some View {
        let d = model.dispatch
        let notams = (ofp.origin.notams ?? []) + (ofp.destination.notams ?? []) + (ofp.alternate?.notams ?? [])
        let unread = notams.filter { !d.notamsRead.contains(Self.notamKey($0)) }.count
        return List {
            Section {
                Text("\(ofp.callsign ?? "OFP") · \(ofp.routeTitle)")
                    .font(.headline)
            }
            Section("Despacho") {
                link("Resumen del vuelo y pesos", icon: "doc.plaintext", done: d.dispatchSigned != nil) { FlightSummaryView() }
                link("Combustible", icon: "fuelpump", detail: d.extraFuelKg > 0 ? "+\(Int(d.extraFuelKg)) kg" : nil) { FuelDecisionView() }
                link("Meteorología", icon: "cloud.sun", warning: [ofp.destination, ofp.alternate].contains { $0?.weatherCategory == "lifr" }) { WeatherView() }
                link("NOTAM", icon: "exclamationmark.bubble", detail: notams.isEmpty ? "sin NOTAM en el OFP" : (unread == 0 ? nil : "\(unread) sin leer"), done: !notams.isEmpty && unread == 0) { NotamView() }
                link("MEL (simulado)", icon: "wrench.and.screwdriver", detail: d.melItems.isEmpty ? nil : "\(d.melItems.count) diferidos") { MELView() }
                link("Tiempo de actividad", icon: "clock") { DutyView() }
                link("Plan ATC y navlog", icon: "list.bullet.rectangle") { FlightPlanView() }
            }
            Section("Briefing") {
                link("ATIS", icon: "antenna.radiowaves.left.and.right", detail: model.atis.letter.map { "Información \($0)" }) { ATISView() }
                link("Autorización de salida", icon: "text.bubble", done: d.clearance.isSquawkValid && d.clearance.initialAltitude != nil) { ClearanceView() }
                link("Briefing de salida", icon: "airplane.departure", done: d.departureBriefed != nil) { DepartureBriefingView() }
                link("Inspección exterior", icon: "figure.walk", detail: "\(d.walkaroundDone.count)/\(WalkaroundPoint.route.count)",
                     done: d.walkaroundDone.count == WalkaroundPoint.route.count) { WalkaroundView() }
            }
        }
    }

    private func link<Destination: View>(_ title: String, icon: String, detail: String? = nil, done: Bool = false,
                                          warning: Bool = false, @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(warning ? PanelTheme.checklistAmber : .secondary)
                }
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(PanelTheme.checklistGreen)
                } else if warning {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(PanelTheme.checklistAmber)
                }
            }
        }
    }

    static func notamKey(_ text: String) -> String {
        String(text.prefix(80))
    }
}

/// Binding into the dispatch state of the model.
private extension PanelModel {
    func dispatchBinding<T>(_ path: WritableKeyPath<DispatchState, T>) -> Binding<T> {
        Binding(get: { self.dispatch[keyPath: path] }, set: { value in self.updateDispatch { $0[keyPath: path] = value } })
    }
}

private func massText(_ ofp: SimBriefOFP, _ value: Double?) -> String {
    guard let kg = ofp.kilograms(value) else { return "—" }
    return "\(Int(kg.rounded())) kg"
}

// MARK: 1.1 · 0.3 · 1.5 Summary, weights and alternates

private struct FlightSummaryView: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if let ofp = model.ofp {
            Form {
                Section("Vuelo") {
                    LabeledContent("Vuelo", value: ofp.callsign ?? "—")
                    LabeledContent("Ruta", value: "\(ofp.origin.icao) → \(ofp.destination.icao)")
                    LabeledContent("Avión", value: [ofp.aircraft, ofp.registration].compactMap { $0 }.joined(separator: " · "))
                    if let out = ofp.scheduledOut { LabeledContent("Salida prevista", value: "\(TurnaroundFormat.local(out)) · \(TurnaroundFormat.utc(out))") }
                    if let ete = ofp.timeEnroute { LabeledContent("Tiempo de vuelo", value: String(format: "%d:%02d", ete / 3600, (ete % 3600) / 60)) }
                    if let distance = ofp.routeDistance { LabeledContent("Distancia", value: "\(distance) NM") }
                    if let altitude = ofp.initialAltitude { LabeledContent("Nivel inicial", value: "FL\(altitude / 100)") }
                    ForEach(Array(ofp.stepClimbList.enumerated()), id: \.offset) { _, step in
                        LabeledContent("Escalón", value: "FL\(step.level) en \(step.fix)")
                    }
                    if let ci = ofp.costIndex { LabeledContent("Cost index", value: "\(ci)") }
                }
                Section {
                    weightRow("ZFW", ofp.weights.zeroFuel, ofp.weights.maxZeroFuel, ofp)
                    weightRow("TOW", ofp.weights.takeoff, ofp.weights.maxTakeoff, ofp)
                    weightRow("LW", ofp.weights.landing, ofp.weights.maxLanding, ofp)
                    if let passengers = ofp.weights.passengers { LabeledContent("Pasajeros", value: "\(passengers)") }
                    LabeledContent("Carga de pago", value: massText(ofp, ofp.weights.payload))
                } header: {
                    Text("Pesos estimados del OFP")
                } footer: {
                    Text("El margen hasta el máximo estructural limita cuánto combustible extra cabe. Los pesos finales llegan en la hoja de carga.")
                }
                Section {
                    if let alternate = ofp.alternate {
                        LabeledContent("Alterno", value: alternate.icao + (alternate.name.map { " · \($0.capitalized)" } ?? ""))
                    }
                    ForEach(ofp.enrouteAlternates ?? [], id: \.icao) { airport in
                        LabeledContent("En ruta", value: airport.icao + (airport.name.map { " · \($0.capitalized)" } ?? ""))
                    }
                    LabeledContent("Combustible al alterno", value: massText(ofp, ofp.fuel.alternate))
                } header: {
                    Text("Alternos")
                }
                if !model.deferredItems.isEmpty {
                    Section("MEL diferidos") {
                        ForEach(model.deferredItems) { item in
                            Text("\(item.ata) · \(item.title)")
                        }
                    }
                }
                Section {
                    if let signed = model.dispatch.dispatchSigned {
                        Label("Despacho aceptado a las \(TurnaroundFormat.utc(signed))", systemImage: "signature")
                            .foregroundStyle(PanelTheme.checklistGreen)
                        Button("Anular") { model.updateDispatch { $0.dispatchSigned = nil } }
                    } else {
                        Button {
                            model.updateDispatch { $0.dispatchSigned = Date() }
                        } label: {
                            Label("Aceptar el despacho", systemImage: "signature")
                        }
                    }
                } footer: {
                    Text("Como la firma del comandante en el OFP: ruta, combustible, pesos, meteorología, NOTAM y MEL revisados.")
                }
            }
            .navigationTitle("Resumen del vuelo")
        }
    }

    private func weightRow(_ title: String, _ value: Double?, _ maximum: Double?, _ ofp: SimBriefOFP) -> some View {
        let kg = ofp.kilograms(value)
        let max = ofp.kilograms(maximum)
        let over = (kg ?? 0) > (max ?? .infinity)
        return LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 1) {
                Text(massText(ofp, value)).foregroundStyle(over ? PanelTheme.checklistAmber : .primary)
                if let kg, let max {
                    Text(over ? "\(Int(kg - max)) kg por encima del máximo" : "margen \(Int(max - kg)) kg (máx \(Int(max)))")
                        .font(.caption).foregroundStyle(over ? PanelTheme.checklistAmber : .secondary)
                }
            }
        }
    }
}

// MARK: 1.2 Fuel decision

private struct FuelDecisionView: View {
    @Environment(PanelModel.self) private var model
    static let reasons = ["Meteorología en destino", "Tráfico o esperas (ATC)", "Slot o retrasos previstos", "MEL",
                          "Tankering (combustible más caro en destino)", "Otros"]

    var body: some View {
        if let ofp = model.ofp {
            let extra = model.dispatch.extraFuelKg
            Form {
                Section {
                    LabeledContent("Rodaje (TAXI)", value: massText(ofp, ofp.fuel.taxi))
                    LabeledContent("Viaje (TRIP)", value: massText(ofp, ofp.fuel.trip))
                    LabeledContent("Contingencia (CONT)", value: massText(ofp, ofp.fuel.contingency))
                    LabeledContent("Alterno (ALTN)", value: massText(ofp, ofp.fuel.alternate))
                    LabeledContent("Reserva final (FINRES)", value: massText(ofp, ofp.fuel.finalReserve))
                    LabeledContent("Extra del OFP", value: massText(ofp, ofp.fuel.extra))
                    LabeledContent("BLOCK del OFP", value: massText(ofp, ofp.fuel.block))
                } header: {
                    Text("Combustible del OFP")
                } footer: {
                    Text("El mínimo legal para salir es rodaje + viaje + contingencia + alterno + reserva final. Lo que pase de ahí es decisión del comandante.")
                }
                Section {
                    Stepper("Extra: \(Int(extra)) kg", value: model.dispatchBinding(\.extraFuelKg), in: 0...6000, step: 100)
                    Picker("Motivo", selection: model.dispatchBinding(\.extraFuelReason)) {
                        Text("Sin motivo").tag("")
                        ForEach(Self.reasons, id: \.self) { Text($0).tag($0) }
                    }
                    if let block = ofp.kilograms(ofp.fuel.block) {
                        LabeledContent("BLOCK final", value: "\(Int((block + extra).rounded())) kg")
                    }
                } header: {
                    Text("Decisión del comandante")
                } footer: {
                    Text("Cada 100 kg extra cuestan unos 3-4 kg de combustible por hora de vuelo en llevarlos. El BLOCK de la guía del MCDU y del turnaround incluye este extra.")
                }
            }
            .navigationTitle("Combustible")
        }
    }
}

// MARK: 1.3 Weather

private struct WeatherView: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if let ofp = model.ofp {
            List {
                airport("Salida", ofp.origin)
                airport("Destino", ofp.destination)
                if let alternate = ofp.alternate { airport("Alterno", alternate) }
            }
            .navigationTitle("Meteorología")
        }
    }

    private func airport(_ role: String, _ airport: SimBriefOFP.Airport) -> some View {
        let category = airport.weatherCategory.flatMap(WeatherCategory.init(rawValue:))
        return Section {
            if let metar = airport.metar {
                Text(metar).font(.footnote.monospaced()).textSelection(.enabled)
            }
            if let taf = airport.taf {
                Text(taf).font(.footnote.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if let advice = category?.advice {
                Label(advice, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(category == .lifr ? PanelTheme.checklistAmber : .secondary)
            }
            if airport.metar == nil && airport.taf == nil {
                Text("El OFP no trae meteorología de este aeropuerto.").foregroundStyle(.secondary)
            }
        } header: {
            HStack {
                Text("\(role) · \(airport.icao)")
                Spacer()
                if let category { Text(category.title) }
            }
        }
    }
}

// MARK: 1.4 NOTAM

private struct NotamView: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if let ofp = model.ofp {
            let groups: [(String, [String])] = [(ofp.origin.icao, ofp.origin.notams ?? []), (ofp.destination.icao, ofp.destination.notams ?? []),
                                                (ofp.alternate?.icao ?? "", ofp.alternate?.notams ?? [])].filter { !$0.1.isEmpty }
            List {
                if groups.isEmpty {
                    Text("Este OFP no trae NOTAM. Actívalos en las opciones de SimBrief o revísalos en la web de tu proveedor.")
                        .foregroundStyle(.secondary)
                }
                ForEach(groups, id: \.0) { group in
                    Section(group.0) {
                        ForEach(group.1, id: \.self) { notam in
                            let key = DispatchSheet.notamKey(notam)
                            let read = model.dispatch.notamsRead.contains(key)
                            Button {
                                model.updateDispatch { state in
                                    if read { state.notamsRead.removeAll { $0 == key } } else { state.notamsRead.append(key) }
                                }
                            } label: {
                                HStack(alignment: .top) {
                                    Image(systemName: read ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(read ? PanelTheme.checklistGreen : .secondary)
                                    Text(notam).font(.footnote.monospaced()).foregroundStyle(read ? .secondary : .primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("NOTAM")
        }
    }
}

// MARK: 1.6 MEL

private struct MELView: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(MELItem.catalog) { item in
                    let deferred = model.dispatch.melItems.contains(item.id)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(isOn: Binding(get: { deferred }, set: { on in
                            model.updateDispatch { state in
                                if on { state.melItems.append(item.id) } else { state.melItems.removeAll { $0 == item.id } }
                            }
                        })) {
                            Text("\(item.ata) · \(item.title)")
                        }
                        if deferred {
                            ForEach(item.consequences, id: \.self) { consequence in
                                Label(consequence, systemImage: "arrow.turn.down.right")
                                    .font(.caption).foregroundStyle(PanelTheme.checklistAmber)
                            }
                        }
                    }
                }
            } footer: {
                Text("Averías diferidas simuladas para practicar la decisión de despacho. Ejemplos simplificados del A320: la MEL real es el documento del operador.")
            }
        }
        .navigationTitle("MEL")
    }
}

// MARK: 1.7 Duty period

private struct DutyView: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        Form {
            Section {
                Stepper("Sectores hoy: \(model.dispatch.sectorsToday)", value: model.dispatchBinding(\.sectorsToday), in: 1...8)
                Stepper("Presentación: \(model.dispatch.reportMinutesBeforeOffBlocks) min antes", value: model.dispatchBinding(\.reportMinutesBeforeOffBlocks), in: 30...120, step: 15)
            }
            if let offBlocks = model.plannedOffBlocks {
                let duty = model.dutyPeriod(offBlocks: offBlocks)
                Section {
                    LabeledContent("Presentación", value: "\(TurnaroundFormat.local(duty.report)) local")
                    LabeledContent("Actividad máxima", value: TurnaroundFormat.minutes(duty.maximumMinutes))
                    LabeledContent("Fin máximo (último IN)", value: "\(TurnaroundFormat.local(duty.maximumEnd)) local")
                    if let ete = model.ofp?.timeEnroute {
                        let arrival = offBlocks.addingTimeInterval(Double(ete) + 20 * 60)
                        LabeledContent("Llegada de este vuelo", value: TurnaroundFormat.local(arrival))
                        if arrival > duty.maximumEnd {
                            Label("Este vuelo terminaría fuera del periodo de actividad", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(PanelTheme.checklistAmber)
                        }
                    }
                } footer: {
                    Text("Tabla de EASA ORO.FTL.205 para tripulación aclimatada, simplificada: depende de la hora local de presentación y baja 30 minutos por sector a partir del tercero (mínimo 9 h).")
                }
            } else {
                Text("Sin hora de salida: planifica el turnaround o carga un OFP con hora.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Tiempo de actividad")
    }
}

// MARK: 0.6 Flight plan and navlog

private struct FlightPlanView: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if let ofp = model.ofp {
            List {
                if let fpl = ofp.atcFlightPlan {
                    Section("Plan ATC presentado") {
                        Text(fpl).font(.footnote.monospaced()).textSelection(.enabled)
                    }
                }
                if let route = ofp.route {
                    Section("Ruta") {
                        Text(route).font(.footnote.monospaced()).textSelection(.enabled)
                    }
                }
                Section {
                    ForEach(Array(ofp.fixes.enumerated()), id: \.offset) { _, fix in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(fix.ident).font(.callout.monospaced().weight(.semibold))
                                Text(fix.airway ?? "").font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let altitude = fix.altitude {
                                Text(altitude >= 10000 ? "FL\(altitude / 100)" : "\(altitude) ft")
                                    .font(.caption.monospacedDigit()).frame(width: 64, alignment: .trailing)
                            }
                            Text(fix.timeTotal.map { String(format: "%d:%02d", $0 / 3600, ($0 % 3600) / 60) } ?? "")
                                .font(.caption.monospacedDigit()).frame(width: 44, alignment: .trailing)
                            Text(massText(ofp, fix.plannedFuel))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 74, alignment: .trailing)
                        }
                    }
                } header: {
                    Text("Navlog: punto · nivel · tiempo · combustible previsto")
                }
            }
            .navigationTitle("Plan y navlog")
        }
    }
}

// MARK: 2.3 ATIS

private struct ATISView: View {
    @Environment(PanelModel.self) private var model
    @State private var applied: String?

    var body: some View {
        let atis = model.atis
        Form {
            if let messages = model.ofp?.origin.atis, !messages.isEmpty {
                Section("ATIS en el OFP") {
                    ForEach(messages, id: \.self) { message in
                        Button {
                            model.updateDispatch { $0.atisText = message }
                        } label: {
                            Text(message).font(.caption.monospaced()).lineLimit(3)
                        }
                    }
                }
            }
            Section {
                TextEditor(text: model.dispatchBinding(\.atisText))
                    .font(.footnote.monospaced())
                    .frame(minHeight: 120)
            } header: {
                Text("Texto del ATIS")
            } footer: {
                Text("Pega o escribe el ATIS (de la radio, de VATSIM o del D-ATIS). La app lee la letra, la pista, el viento, la temperatura, el QNH y el nivel de transición.")
            }
            if !atis.isEmpty {
                Section("Lo que dice") {
                    if let letter = atis.letter { LabeledContent("Información", value: letter) }
                    if let runway = atis.runway { LabeledContent("Pista", value: runway) }
                    if let speed = atis.windSpeed {
                        LabeledContent("Viento", value: (atis.windDirection.map { String(format: "%03d", $0) } ?? "VRB") + "/\(speed)" + (atis.gust.map { "G\($0)" } ?? "") + " kt")
                    }
                    if let temperature = atis.temperature { LabeledContent("Temperatura", value: "\(temperature) °C" + (atis.dewpoint.map { " · rocío \($0)" } ?? "")) }
                    if let qnh = atis.qnh { LabeledContent("QNH", value: "\(qnh) hPa") }
                    if let level = atis.transitionLevel { LabeledContent("Nivel de transición", value: "FL\(level)") }
                }
                Section {
                    Button("Poner el QNH en los BARO") {
                        applied = model.applyATISQNH() ? "QNH \(atis.qnh ?? 0) puesto en los BARO" : "Sin BARO conectado"
                    }
                    .disabled(atis.qnh == nil || model.status != .connected)
                    Button("Usar la pista en la autorización") {
                        if let runway = atis.runway { model.updateDispatch { $0.clearance.runway = runway } }
                    }
                    .disabled(atis.runway == nil)
                    if let applied { Text(applied).font(.caption).foregroundStyle(.secondary) }
                } footer: {
                    Text("La temperatura y el viento sirven para comprobar el cálculo de despegue (TLR) de SimBrief: si han cambiado mucho, recalcula.")
                }
            }
        }
        .navigationTitle("ATIS")
    }
}

// MARK: 2.4 Clearance

private struct ClearanceView: View {
    @Environment(PanelModel.self) private var model
    @State private var applied: String?

    var body: some View {
        let clearance = model.dispatch.clearance
        Form {
            Section {
                TextField("SID", text: model.dispatchBinding(\.clearance.sid))
                    .textInputAutocapitalization(.characters)
                TextField("Pista", text: model.dispatchBinding(\.clearance.runway))
                    .textInputAutocapitalization(.characters)
                TextField("Altitud inicial (ft)", value: model.dispatchBinding(\.clearance.initialAltitude), format: .number)
                    .keyboardType(.numberPad)
                TextField("Código de transpondedor", text: model.dispatchBinding(\.clearance.squawk))
                    .keyboardType(.numberPad)
                TextField("Frecuencia de salida", text: model.dispatchBinding(\.clearance.departureFrequency))
                    .keyboardType(.decimalPad)
            } header: {
                Text("Autorización")
            } footer: {
                if !clearance.squawk.isEmpty && !clearance.isSquawkValid {
                    Text("El código son cuatro cifras del 0 al 7.").foregroundStyle(PanelTheme.checklistAmber)
                }
            }
            Section("Colación") {
                Text(readback(clearance))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            Section {
                Button("Poner el código en el transpondedor") {
                    model.applySquawk()
                    applied = "Código \(clearance.squawk) tecleado en el panel ATC"
                }
                .disabled(!clearance.isSquawkValid || model.status != .connected)
                Button("Poner la altitud inicial en el FCU") {
                    applied = model.applyInitialAltitude() ? "ALT \(clearance.initialAltitude ?? 0) en el FCU" : "No se pudo poner en el FCU"
                }
                .disabled(clearance.initialAltitude == nil || model.status != .connected)
                if let applied { Text(applied).font(.caption).foregroundStyle(.secondary) }
            } footer: {
                if let sid = model.ofp?.sid, !clearance.sid.isEmpty, clearance.sid.uppercased() != sid.uppercased() {
                    Text("La SID autorizada (\(clearance.sid)) no es la del OFP (\(sid)): cámbiala en el F-PLN del MCDU.")
                        .foregroundStyle(PanelTheme.checklistAmber)
                }
            }
        }
        .navigationTitle("Autorización de salida")
    }

    private func readback(_ clearance: DepartureClearance) -> String {
        var parts = ["Cleared to \(model.ofp?.destination.icao ?? "…")"]
        if !clearance.sid.isEmpty { parts.append("\(clearance.sid) departure") }
        if !clearance.runway.isEmpty { parts.append("runway \(clearance.runway)") }
        if let altitude = clearance.initialAltitude { parts.append(altitude >= 10000 ? "climb FL\(altitude / 100)" : "climb \(altitude) feet") }
        if !clearance.squawk.isEmpty { parts.append("squawk \(clearance.squawk)") }
        if !clearance.departureFrequency.isEmpty { parts.append("departure \(clearance.departureFrequency)") }
        return parts.joined(separator: ", ") + ", \(model.ofp?.callsign ?? "")"
    }
}

// MARK: 2.1 · 2.2 · 4.3 Departure briefing and SID constraints

private struct DepartureBriefingView: View {
    @Environment(PanelModel.self) private var model
    @State private var newFix = ""
    @State private var newKind: AltitudeConstraint.Kind = .atOrAbove
    @State private var newAltitude = ""
    @State private var newSpeed = ""

    var body: some View {
        if let ofp = model.ofp {
            let clearance = model.dispatch.clearance
            let sidFixes = ofp.fixes.prefix { $0.isProcedure ?? false }.map(\.ident)
            Form {
                Section("Salida") {
                    LabeledContent("Pista", value: clearance.runway.isEmpty ? (ofp.origin.runway ?? "—") : clearance.runway)
                    LabeledContent("SID", value: clearance.sid.isEmpty ? (ofp.sid ?? "—") : clearance.sid)
                    LabeledContent("Altitud inicial", value: clearance.initialAltitude.map { "\($0) ft" } ?? "falta la autorización")
                    if let trans = ofp.origin.transitionAltitude { LabeledContent("Altitud de transición", value: "\(trans) ft") }
                    if let takeoff = ofp.takeoff {
                        LabeledContent("Configuración", value: [takeoff.flaps.map { "Flaps \($0)" }, takeoff.flexTemperature.map { "FLEX \($0)" } ?? "TOGA"]
                            .compactMap { $0 }.joined(separator: " · "))
                        LabeledContent("V1 · VR · V2", value: [takeoff.v1, takeoff.vr, takeoff.v2].map { speed in speed.map { "\($0)" } ?? "—" }.joined(separator: " · "))
                    }
                }
                Section {
                    TextField("Procedimiento de fallo de motor (EOSID)", text: model.dispatchBinding(\.engineOutProcedure), axis: .vertical)
                    TextField("Altitud de aceleración con motor parado (ft)", value: model.dispatchBinding(\.accelerationAltitude), format: .number)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Fallo de motor")
                } footer: {
                    Text("Antes de V1, se aborta. Después, se sigue: V2, rumbo o trayectoria del EOSID (si no hay, la SID), y a la altitud de aceleración se acelera y se recogen flaps. Muchas aerolíneas cargan el EOSID en el SEC F-PLN.")
                }
                Section {
                    ForEach(model.dispatch.sidConstraints) { constraint in
                        Text(constraint.text).font(.callout.monospaced())
                    }
                    .onDelete { offsets in
                        model.updateDispatch { state in
                            for index in offsets.sorted(by: >) { state.sidConstraints.remove(at: index) }
                        }
                    }
                    if !sidFixes.isEmpty {
                        Picker("Punto", selection: $newFix) {
                            Text("Elige").tag("")
                            ForEach(Array(Set(sidFixes)).sorted(), id: \.self) { Text($0).tag($0) }
                        }
                    } else {
                        TextField("Punto", text: $newFix).textInputAutocapitalization(.characters)
                    }
                    Picker("Tipo", selection: $newKind) {
                        Text("A (o más)").tag(AltitudeConstraint.Kind.atOrAbove)
                        Text("B (o menos)").tag(AltitudeConstraint.Kind.atOrBelow)
                        Text("= (exacta)").tag(AltitudeConstraint.Kind.at)
                    }
                    .pickerStyle(.segmented)
                    TextField("Altitud (ft)", text: $newAltitude).keyboardType(.numberPad)
                    TextField("Velocidad máxima (kt, opcional)", text: $newSpeed).keyboardType(.numberPad)
                    Button("Añadir restricción") {
                        guard let altitude = Int(newAltitude), !newFix.isEmpty else { return }
                        let constraint = AltitudeConstraint(fix: newFix.uppercased(), kind: newKind, altitude: altitude, speed: Int(newSpeed))
                        model.updateDispatch { $0.sidConstraints.append(constraint) }
                        newFix = ""
                        newAltitude = ""
                        newSpeed = ""
                    }
                    .disabled(Int(newAltitude) == nil || newFix.isEmpty)
                } header: {
                    Text("Restricciones de la SID (carta de Navigraph)")
                } footer: {
                    Text("El OFP no trae las restricciones de la carta: anótalas en el briefing. En vuelo, al pasar cada punto, la app avisa (sin botones) si lo cruzas fuera de la restricción. Además vigila salirte de la altitud capturada en el FCU y pasar de 250 kt por debajo de FL100.")
                }
                Section {
                    TextField("Amenazas: meteorología, terreno, tráfico, pista, NOTAM, MEL, fatiga…", text: model.dispatchBinding(\.threats), axis: .vertical)
                } header: {
                    Text("Amenazas (TEM)")
                }
                Section {
                    if let briefed = model.dispatch.departureBriefed {
                        Label("Briefing hecho a las \(TurnaroundFormat.utc(briefed))", systemImage: "checkmark.seal")
                            .foregroundStyle(PanelTheme.checklistGreen)
                    } else {
                        Button {
                            model.updateDispatch { $0.departureBriefed = Date() }
                        } label: {
                            Label("Briefing de salida hecho", systemImage: "checkmark.seal")
                        }
                    }
                }
            }
            .navigationTitle("Briefing de salida")
        }
    }
}

// MARK: 2.5 Walkaround

private struct WalkaroundView: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        List {
            Section {
                ForEach(WalkaroundPoint.route) { point in
                    let done = model.dispatch.walkaroundDone.contains(point.id)
                    Button {
                        model.updateDispatch { state in
                            if done { state.walkaroundDone.removeAll { $0 == point.id } } else { state.walkaroundDone.append(point.id) }
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(done ? PanelTheme.checklistGreen : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(point.area).font(.callout.weight(.semibold))
                                Text(point.checks).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } footer: {
                Text("En el sentido de las agujas del reloj desde el morro, como en la inspección de las aerolíneas. En el simulador, con la vista exterior.")
            }
        }
        .navigationTitle("Inspección exterior")
    }
}

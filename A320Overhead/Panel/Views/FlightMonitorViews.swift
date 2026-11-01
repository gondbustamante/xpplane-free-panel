import SwiftUI
import XPlaneKit

/// The flight against the OFP, live from X-Plane: route and fuel, step climbs, descent profile,
/// approach briefing and gates, the touchdown, position reports and the nearest airports.
struct FlightMonitorColumn: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if model.ofp == nil {
            emptyState("Carga tu OFP de SimBrief", detail: "El monitor compara el vuelo con el plan: combustible en cada punto, punto de descenso y aeropuertos cercanos.", icon: "doc.text.magnifyingglass") {
                Button("Abrir la guía para cargarlo") { model.inspectorPanel = .mcduGuide }
                    .buttonStyle(.bordered)
            }
        } else if model.flightData == nil {
            emptyState("Conecta con X-Plane", detail: model.demoMode
                       ? "En el modo demo el avión no vuela: el monitor necesita la posición, la altitud y el combustible del simulador."
                       : "El monitor lee la posición, la altitud, la velocidad y el combustible del avión.",
                       icon: "antenna.radiowaves.left.and.right") { EmptyView() }
        } else {
            TimelineView(.periodic(from: .now, by: 2)) { _ in
                monitor
            }
        }
    }

    private func emptyState<Actions: View>(_ title: String, detail: String, icon: String,
                                           @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            actions()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var monitor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                RouteFuelCard()
                DepartureCard()
                CruiseCard()
                DescentCard()
                ApproachCard()
                if let landing = model.lastLanding {
                    LandingCard(report: landing)
                }
                PositionReportsCard()
                NearbyAirportsCard()
                Text("Monitor orientativo para simulación, calculado con el OFP de SimBrief y los datos de X-Plane.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
        }
    }
}

/// Card frame shared by the monitor sections.
private struct MonitorCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .tracking(0.6)
                .foregroundStyle(PanelTheme.checklistCyan)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

private struct Row: View {
    let label: String
    let value: String
    var colour: Color = .white

    var body: some View {
        HStack {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.footnote.monospacedDigit().weight(.semibold)).foregroundStyle(colour)
        }
    }
}

enum MonitorFormat {
    static func minutes(distance: Double, groundspeed: Double) -> String? {
        guard groundspeed > 60 else { return nil }
        let minutes = Int((distance / groundspeed * 60).rounded())
        return minutes >= 60 ? String(format: "%d h %02d min", minutes / 60, minutes % 60) : "\(minutes) min"
    }

    static func kg(_ value: Double) -> String {
        "\(Int(value.rounded())) kg"
    }

    static func signedKg(_ value: Double) -> String {
        (value >= 0 ? "+" : "−") + "\(Int(abs(value).rounded())) kg"
    }
}

// MARK: Route and fuel (5.1)

private struct RouteFuelCard: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        MonitorCard(title: "RUTA Y COMBUSTIBLE", icon: "fuelpump") {
            if let ofp = model.ofp, let data = model.flightData {
                if let progress = model.routeProgress, ofp.fixes.indices.contains(progress.next) {
                    let next = ofp.fixes[progress.next]
                    Row(label: "Siguiente punto", value: "\(next.ident) · \(Int(progress.distanceToNext.rounded())) NM"
                        + (MonitorFormat.minutes(distance: progress.distanceToNext, groundspeed: data.groundspeed).map { " · \($0)" } ?? ""))
                    Row(label: "Hasta \(ofp.destination.icao)", value: "\(Int(progress.distanceToGo.rounded())) NM"
                        + (MonitorFormat.minutes(distance: progress.distanceToGo, groundspeed: data.groundspeed).map { " · \($0)" } ?? ""))
                } else {
                    Text(data.onGround ? "En tierra: el seguimiento empieza al despegar." : "Fuera de la ruta del OFP.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Row(label: "A bordo", value: MonitorFormat.kg(data.fuelKg))
                if let status = model.fuelStatus {
                    Row(label: "Frente al plan", value: MonitorFormat.signedKg(status.deviation),
                        colour: status.deviation < -300 ? PanelTheme.checklistAmber : PanelTheme.checklistGreen)
                    Row(label: "Previsto en destino", value: MonitorFormat.kg(status.estimatedLanding),
                        colour: status.level == .onPlan ? PanelTheme.checklistGreen : PanelTheme.checklistAmber)
                    if let reserve = ofp.kilograms(ofp.fuel.finalReserve) {
                        Row(label: "Reserva final · + alterno", value: "\(Int(reserve)) · \(Int(reserve + (ofp.kilograms(ofp.fuel.alternate) ?? 0))) kg")
                    }
                    FuelLevelLabel(level: status.level)
                }
            }
        }
    }
}

private struct FuelLevelLabel: View {
    let level: FuelStatus.Level

    var body: some View {
        switch level {
        case .onPlan:
            Label("Combustible según el plan", systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(PanelTheme.checklistGreen)
        case .watch:
            Label("Gastas más de lo previsto: revisa viento, nivel y velocidad (FUEL PRED)", systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(PanelTheme.checklistAmber)
        case .noAlternate:
            Label("Ya no llegas al alterno con la reserva final: decide ahora si desviar o comprometerte con el destino (y declara MINIMUM FUEL si cualquier cambio te dejaría por debajo de la reserva)", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(PanelTheme.checklistAmber)
        case .mayday:
            Label("MAYDAY FUEL: aterrizarías por debajo de la reserva final. Declara emergencia y aterriza en el aeropuerto adecuado más cercano", systemImage: "exclamationmark.octagon.fill")
                .font(.caption.weight(.semibold)).foregroundStyle(.red)
        }
    }
}

// MARK: Cruise (5.3)

private struct CruiseCard: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if let ofp = model.ofp, let data = model.flightData, !data.onGround {
            let passed = model.routeProgress?.lastPassed ?? -1
            let nextStep = ofp.stepClimbList.first { step in
                (ofp.fixes.firstIndex { $0.ident == step.fix } ?? Int.max) > passed
            }
            MonitorCard(title: "CRUCERO", icon: "airplane") {
                Row(label: "Nivel actual", value: "FL\(Int((data.altitude / 100).rounded()))")
                if let planned = ofp.initialAltitude {
                    Row(label: "Nivel del plan", value: "FL\(planned / 100)")
                }
                if let step = nextStep {
                    Row(label: "Próximo escalón", value: "FL\(step.level) en \(step.fix)")
                    Text("Pide el ascenso al pasar \(step.fix): el plan sube al aligerarse el avión. Compruébalo con el nivel óptimo de PROG.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: Descent (6.1)

private struct DescentCard: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if let progress = model.routeProgress, let data = model.flightData, !data.onGround {
            let elevation = model.destinationElevation
            let required = DescentProfile.requiredDistance(altitude: data.altitude, destinationElevation: elevation)
            let toTOD = progress.distanceToGo - required
            let descending = data.verticalSpeed < -500 || toTOD <= 0
            MonitorCard(title: "DESCENSO", icon: "arrow.down.right") {
                if !descending {
                    Row(label: "TOD (regla de 3)", value: "en \(Int(toTOD.rounded())) NM"
                        + (MonitorFormat.minutes(distance: toTOD, groundspeed: data.groundspeed).map { " · \($0)" } ?? ""))
                    Text("Altitud en miles × 3 + 10 NM para frenar y configurar. Con viento de cola, empieza antes; de cara, después.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    let deviation = DescentProfile.deviation(altitude: data.altitude, distanceToGo: progress.distanceToGo,
                                                             destinationElevation: elevation)
                    let ideal = DescentProfile.idealAltitude(distanceToGo: progress.distanceToGo, destinationElevation: elevation)
                    Row(label: "Perfil a \(Int(progress.distanceToGo.rounded())) NM", value: "\(Int(ideal.rounded())) ft")
                    Row(label: "Desviación", value: abs(deviation) < 500 ? "En perfil"
                        : (deviation > 0 ? "\(Int(deviation.rounded())) ft alto" : "\(Int((-deviation).rounded())) ft bajo"),
                        colour: abs(deviation) < 1000 ? PanelTheme.checklistGreen : PanelTheme.checklistAmber)
                    if deviation > 1000 {
                        Text("Alto: aerofrenos, más velocidad o pide más millas (vectores). Configura antes si hace falta.")
                            .font(.caption).foregroundStyle(PanelTheme.checklistAmber)
                    } else if deviation < -1000 {
                        Text("Bajo: reduce el régimen (V/S) o nivela hasta cortar el perfil.")
                            .font(.caption).foregroundStyle(PanelTheme.checklistAmber)
                    }
                }
            }
        }
    }
}

// MARK: Approach (6.2, 6.3, 6.4)

private struct ApproachCard: View {
    @Environment(PanelModel.self) private var model
    @State private var showBriefing = false

    var body: some View {
        @Bindable var model = model
        if let ofp = model.ofp {
            MonitorCard(title: "APROXIMACIÓN", icon: "airplane.arrival") {
                DisclosureGroup(isExpanded: $showBriefing) {
                    briefing(ofp)
                } label: {
                    Text("Briefing de aproximación").font(.footnote.weight(.semibold))
                }
                if model.gateResults.isEmpty {
                    Text("Comprobación de aproximación estabilizada a 1000 y 500 ft sobre el campo: configuración de aterrizaje, tren, velocidad VAPP −5/+10, régimen hasta 1000 ft/min y dentro de un punto de LOC y senda.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.gateResults) { gate in
                    Label {
                        Text(gate.isStable ? "\(gate.gate) ft: estable" : "\(gate.gate) ft: \(gate.failures.joined(separator: ", "))")
                    } icon: {
                        Image(systemName: gate.isStable ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    }
                    .font(.footnote)
                    .foregroundStyle(gate.isStable ? PanelTheme.checklistGreen : PanelTheme.checklistAmber)
                }
                Toggle("Llamadas por voz", isOn: $model.voiceCallouts)
                    .font(.footnote)
            }
        }
    }

    private func briefing(_ ofp: SimBriefOFP) -> some View {
        let raw = model.rawValues
        func value(_ name: String) -> Double? { raw[name]?.doubleValue.flatMap { $0 != 0 ? $0 : nil } }
        let data = model.flightData
        return VStack(alignment: .leading, spacing: 4) {
            Row(label: "Destino · pista", value: "\(ofp.destination.icao) · \(ofp.destination.runway ?? "—")")
            if let star = ofp.star { Row(label: "STAR", value: star + (ofp.starTransition.map { " (\($0))" } ?? "")) }
            if let ils = ofp.landingILSFrequency { Row(label: "ILS", value: ils) }
            if let level = ofp.destination.transitionLevel { Row(label: "Nivel de transición", value: "FL\(level / 100)") }
            if let qnh = value("toliss_airbus/performance/DestQNH") { Row(label: "QNH (PERF APPR)", value: String(format: qnh > 100 ? "%.0f" : "%.2f", qnh)) }
            if let direction = value("toliss_airbus/performance/DestWindDir"), let speed = value("toliss_airbus/performance/DestWindSpd") {
                Row(label: "Viento (PERF APPR)", value: String(format: "%03.0f/%.0f kt", direction, speed))
            }
            if let dh = data?.decisionHeight { Row(label: "Mínimos (DH, radio)", value: "\(Int(dh)) ft") }
            else if let mda = data?.minimumAltitude { Row(label: "Mínimos (MDA, baro)", value: "\(Int(mda)) ft") }
            else { Row(label: "Mínimos", value: "sin introducir en PERF APPR", colour: PanelTheme.checklistAmber) }
            if let status = model.fuelStatus { Row(label: "Combustible previsto", value: MonitorFormat.kg(status.estimatedLanding)) }
            if let alternate = ofp.alternate { Row(label: "Alterno", value: alternate.icao) }
            Text("Amenazas (TEM): meteorología, terreno y altitudes mínimas, tráfico, pista (estado, salida, rodaje), fatiga. Frustrada: altitud y procedimiento de la carta; configuración y autobrake de aterrizaje.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.top, 4)
        }
    }
}

// MARK: Landing (7.1)

private struct LandingCard: View {
    let report: LandingReport

    var body: some View {
        MonitorCard(title: "ÚLTIMA TOMA", icon: "airplane.arrival") {
            Row(label: "Régimen", value: "\(report.rate) ft/min", colour: report.isHard ? PanelTheme.checklistAmber : PanelTheme.checklistGreen)
            Row(label: "Factor de carga", value: String(format: "%.2f g", report.peakG))
            if let speed = report.speed { Row(label: "Velocidad", value: "\(speed) kt") }
            Text(report.rating)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(report.isHard ? PanelTheme.checklistAmber : PanelTheme.checklistGreen)
            Text("Una toma de 100-240 ft/min es lo buscado; por encima de 600 ft/min o 2,6 g se considera toma dura y el avión necesita inspección.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: Position reports (5.5)

private struct PositionReportsCard: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if !model.positionReports.isEmpty {
            MonitorCard(title: "INFORMES DE POSICIÓN", icon: "list.bullet.rectangle") {
                ForEach(model.positionReports.suffix(12).reversed()) { report in
                    HStack {
                        Text(report.ident).font(.footnote.monospaced().weight(.semibold))
                        Text(TurnaroundFormat.utc(report.date)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        if let altitude = report.altitude {
                            Text("FL\(altitude / 100)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        if let deviation = report.deviation {
                            Text(MonitorFormat.signedKg(deviation))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(deviation < -300 ? PanelTheme.checklistAmber : PanelTheme.checklistGreen)
                        }
                    }
                }
                Text("Combustible real frente al del plan en cada punto, como en el registro de navegación del OFP.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: Departure: SID constraints from the briefing and deferred items (4.3, 1.6)

private struct DepartureCard: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        let constraints = model.dispatch.sidConstraints
        let deferred = model.deferredItems
        if !constraints.isEmpty || !deferred.isEmpty {
            MonitorCard(title: "SALIDA Y MEL", icon: "airplane.departure") {
                ForEach(constraints) { constraint in
                    let report = model.positionReports.last { $0.ident.uppercased() == constraint.fix.uppercased() }
                    let problems = report?.altitude.map { constraint.violations(altitude: Double($0), speed: nil) }
                    HStack {
                        Text(constraint.text).font(.footnote.monospaced())
                        Spacer()
                        if let report, let altitude = report.altitude {
                            Text("\(altitude) ft").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Image(systemName: problems?.isEmpty ?? true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(problems?.isEmpty ?? true ? PanelTheme.checklistGreen : PanelTheme.checklistAmber)
                        } else {
                            Text("pendiente").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(deferred) { item in
                    Label("\(item.ata) · \(item.title)", systemImage: "wrench.and.screwdriver")
                        .font(.caption).foregroundStyle(PanelTheme.checklistAmber)
                }
            }
        }
    }
}

// MARK: Nearest airports (5.4)

private struct NearbyAirportsCard: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        let airports = model.nearbyAirports.prefix(4)
        if !airports.isEmpty {
            MonitorCard(title: "AEROPUERTOS DEL PLAN MÁS CERCANOS", icon: "mappin.and.ellipse") {
                ForEach(Array(airports.enumerated()), id: \.offset) { _, item in
                    Row(label: item.airport.icao + (item.airport.name.map { " · \($0.capitalized)" } ?? ""),
                        value: "\(Int(item.distance.rounded())) NM")
                }
                Text("Destino, alternos y origen del OFP, por distancia: el punto de partida si hay que desviar.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// Banner over the panel for callouts, gate results, fuel states and the touchdown. Nothing to
/// press: it goes away by itself (6 s for information, 10 s for warnings, 20 s for critical
/// ones) and lets touches through to the panel underneath, so it never asks for attention
/// with buttons while flying. The monitor column keeps the full picture.
struct FlightAlertBanner: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let alert = model.flightAlert,
               context.date.timeIntervalSince(alert.date) < lifetime(alert.level) {
                HStack(spacing: 10) {
                    Image(systemName: icon(alert.level))
                    Text(alert.text)
                        .font(.callout.weight(.semibold))
                        .multilineTextAlignment(.leading)
                }
                .foregroundStyle(colour(alert.level))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.ultraThinMaterial))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(colour(alert.level).opacity(0.7), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                .padding(.horizontal, 60)
                .padding(.top, 10)
                .frame(maxWidth: 640)
                .transition(.move(edge: .top).combined(with: .opacity))
                .allowsHitTesting(false)
            }
        }
    }

    private func lifetime(_ level: PanelModel.FlightAlert.Level) -> TimeInterval {
        switch level {
        case .info, .good: return 6
        case .warning: return 10
        case .critical: return 20
        }
    }

    private func icon(_ level: PanelModel.FlightAlert.Level) -> String {
        switch level {
        case .info: return "info.circle.fill"
        case .good: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private func colour(_ level: PanelModel.FlightAlert.Level) -> Color {
        switch level {
        case .info: return PanelTheme.checklistCyan
        case .good: return PanelTheme.checklistGreen
        case .warning: return PanelTheme.checklistAmber
        case .critical: return .red
        }
    }
}

import Foundation

// Walk through a SimBrief OFP into the MCDU, in the order line pilots use (DATA, INIT A, F-PLN,
// SEC F-PLN, RAD NAV, INIT B, PERF). Each step says which page and line select key, what to type,
// where that figure is in the OFP, why it goes in and what it changes. Where ToLiss publishes
// the value (`toliss_airbus/init/*`, `toliss_airbus/performance/*`) the entry carries a check, so
// the panel can confirm what the MCDU holds.

/// Compares a ToLiss dataref with what the OFP asks for. The units ToLiss uses for each value
/// are not confirmed, so masses match in tonnes or kilograms and levels in FL or feet.
public struct GuideCheck: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Tonnes (or klb) on the MCDU.
        case mass
        /// Speeds, cost index, temperatures, altitudes in feet.
        case number
        /// Flight level on the MCDU.
        case flightLevel
        case text
    }

    public let dataref: String
    public let kind: Kind
    public let expected: Double
    public let expectedText: String?

    public init(dataref: String, kind: Kind, expected: Double = 0, expectedText: String? = nil) {
        self.dataref = dataref
        self.kind = kind
        self.expected = expected
        self.expectedText = expectedText
    }

    /// True when the MCDU holds the OFP value, false when it holds another one, nil while
    /// unknown or not entered yet.
    public func matches(_ value: XPValue?) -> Bool? {
        guard let value else { return nil }
        if kind == .text {
            guard let text = value.textValue?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
            return text.uppercased() == expectedText?.uppercased()
        }
        guard let raw = value.doubleValue else { return nil }
        if raw == 0 && expected != 0 { return nil }
        switch kind {
        case .mass:
            return abs(raw - expected) <= 0.15 || abs(raw / 1000 - expected) <= 0.15
        case .flightLevel:
            return abs(raw - expected) <= 0.5 || abs(raw / 100 - expected) <= 0.5
        case .number:
            return abs(raw - expected) <= 1
        case .text:
            return nil
        }
    }
}

/// One value to type: label, scratchpad text and, when ToLiss shows it, a check.
public struct GuideEntry: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    /// Exactly what goes in the scratchpad.
    public let value: String
    /// Line select key, when different from the step's.
    public let location: String?
    public let check: GuideCheck?

    public init(id: String, label: String, value: String, location: String? = nil, check: GuideCheck? = nil) {
        self.id = id
        self.label = label
        self.value = value
        self.location = location
        self.check = check
    }
}

public struct MCDUGuideStep: Sendable, Equatable, Identifiable {
    public let id: String
    /// MCDU page: "INIT A", "F-PLN", "PERF TAKE OFF"…
    public let page: String
    /// Field on the page.
    public let field: String
    /// Where on the page: line select key or how to get there.
    public let location: String
    public let entries: [GuideEntry]
    /// What to select or check when nothing is typed (runway and SID, totals).
    public let display: String?
    /// Where the figure is in the OFP.
    public let source: String
    public let why: String
    public let affects: String?
    public let optional: Bool
    /// Done later in flight (arrival, approach), not at the gate.
    public let later: Bool

    public init(id: String, page: String, field: String, location: String, entries: [GuideEntry] = [],
                display: String? = nil, source: String, why: String, affects: String? = nil,
                optional: Bool = false, later: Bool = false) {
        self.id = id
        self.page = page
        self.field = field
        self.location = location
        self.entries = entries
        self.display = display
        self.source = source
        self.why = why
        self.affects = affects
        self.optional = optional
        self.later = later
    }

    /// The MCDU page title that shows this step ("INIT", "TAKE OFF", "F-PLN"…).
    public var screenTitles: [String] {
        switch page {
        case let page where page.hasPrefix("DATA"): return ["DATA", "A/C STATUS", "STATUS"]
        case let page where page.hasPrefix("INIT B"): return ["INIT", "FUEL PRED"]
        case let page where page.hasPrefix("INIT"): return ["INIT"]
        case let page where page.hasPrefix("SEC"): return ["SEC"]
        case let page where page.hasPrefix("F-PLN"): return ["F-PLN", "DEPARTURE", "ARRIVAL", "AIRWAYS", "LAT REV", "VERT REV"]
        case let page where page.hasPrefix("RAD NAV"): return ["RADIO NAV"]
        case let page where page.hasPrefix("PERF APPR"): return ["APPR"]
        case let page where page.hasPrefix("PERF"): return ["TAKE OFF", "CLB", "CRZ", "DES"]
        default: return [page]
        }
    }
}

public enum MCDUGuide {
    /// ToLiss datarefs the checks read.
    public static let datarefs = [
        "toliss_airbus/init/ZFW", "toliss_airbus/init/ZFWCG", "toliss_airbus/init/BlockFuel",
        "toliss_airbus/init/costindex", "toliss_airbus/init/cruise_alt", "toliss_airbus/init/flight_no",
        "toliss_airbus/performance/V1", "toliss_airbus/performance/VR", "toliss_airbus/performance/V2",
        "toliss_airbus/performance/flextemp", "toliss_airbus/performance/DeptTrans",
    ]

    /// "61.2": a mass in the OFP's unit as the MCDU takes it (tonnes or thousands of pounds).
    static func mcduMass(_ value: Double?) -> String? {
        value.map { String(format: "%.1f", $0 / 1000) }
    }

    static func time(_ seconds: Int?) -> String? {
        seconds.map { String(format: "%d:%02d", $0 / 3600, ($0 % 3600) / 60) }
    }

    /// `extraFuel`: fuel the captain adds over the OFP, in the OFP's unit; it goes on the BLOCK.
    public static func steps(for ofp: SimBriefOFP, extraFuel: Double = 0) -> [MCDUGuideStep] {
        var steps: [MCDUGuideStep] = []
        let unit = ofp.massUnit
        let o = ofp.origin.icao
        let d = ofp.destination.icao

        // DATA
        steps.append(MCDUGuideStep(
            id: "data_airac", page: "DATA · A/C STATUS", field: "Base de navegación", location: "Línea ACTIVE",
            display: ofp.airac.map { "El OFP usa el AIRAC \($0): el ACTIVE del MCDU debe ser el mismo ciclo" } ?? "Comprueba que el ciclo ACTIVE está en vigor",
            source: "Cabecera del OFP: «AIRAC»",
            why: "SimBrief calculó la ruta, la SID y la STAR con ese ciclo. Con otro, un procedimiento puede llamarse distinto o no existir.",
            affects: "Qué SID, STAR, aerovías y frecuencias encuentra el FMGS."))

        // INIT A
        steps.append(MCDUGuideStep(
            id: "init_fromto", page: "INIT A", field: "FROM/TO", location: "LSK 1R",
            entries: [GuideEntry(id: "fromto", label: "FROM/TO", value: "\(o)/\(d)")],
            source: "Primera línea del OFP: «\(o)-\(d)»",
            why: "Es la base del plan: sin origen y destino no hay F-PLN, ni pistas, ni predicciones.",
            affects: "Carga los dos aeropuertos y sus pistas, crea el F-PLN y da a la presurización la elevación de destino\(ofp.destination.elevation.map { " (\($0) ft)" } ?? "")."))
        if let alternate = ofp.alternate {
            steps.append(MCDUGuideStep(
                id: "init_altn", page: "INIT A", field: "ALTN/CO RTE", location: "LSK 2L",
                entries: [GuideEntry(id: "altn", label: "ALTN", value: alternate.icao)],
                source: "Bloque ALTN del OFP: «\(alternate.icao)»\(alternate.name.map { " (\($0))" } ?? "")",
                why: "El alterno es donde irías si no puedes aterrizar en destino; el OFP lleva combustible para llegar a él.",
                affects: "Combustible y ruta al alterno (ALTN en INIT B) y la opción de activarlo en vuelo."))
        }
        if let callsign = ofp.callsign {
            steps.append(MCDUGuideStep(
                id: "init_flt", page: "INIT A", field: "FLT NBR", location: "LSK 3L",
                entries: [GuideEntry(id: "flt", label: "FLT NBR", value: callsign,
                                     check: GuideCheck(dataref: "toliss_airbus/init/flight_no", kind: .text, expectedText: callsign))],
                source: "«ATC CALLSIGN» de la cabecera del OFP (casilla 7 del plan ATC)",
                why: "Identifica el vuelo en los enlaces de datos con la compañía y el control.",
                affects: "Solo la identificación (ACARS, CPDLC). No cambia la navegación ni el rendimiento."))
        }
        if let ci = ofp.costIndex {
            steps.append(MCDUGuideStep(
                id: "init_ci", page: "INIT A", field: "COST INDEX", location: "LSK 5L",
                entries: [GuideEntry(id: "ci", label: "CI", value: "\(ci)",
                                     check: GuideCheck(dataref: "toliss_airbus/init/costindex", kind: .number, expected: Double(ci)))],
                source: "«CI» de la cabecera del OFP (perfil de crucero «CI \(ci)»)",
                why: "El combustible del OFP está calculado volando con este cost index. Con otro, las predicciones del MCDU no cuadrarán con el plan.",
                affects: "Velocidades ECON de ascenso, crucero y descenso: consumo y hora de llegada."))
        }
        if let altitude = ofp.initialAltitude {
            let level = altitude / 100
            let temperature = ofp.cruiseTemperature.map { "/\($0)" } ?? ""
            let deviation = ofp.averageTemperatureDeviation.map { $0 >= 0 ? "ISA+\($0)" : "ISA\($0)" } ?? "ISA"
            steps.append(MCDUGuideStep(
                id: "init_crz", page: "INIT A", field: "CRZ FL/TEMP", location: "LSK 6L",
                entries: [GuideEntry(id: "crz", label: "CRZ FL/TEMP", value: "\(level)\(temperature)",
                                     check: GuideCheck(dataref: "toliss_airbus/init/cruise_alt", kind: .flightLevel, expected: Double(level)))],
                source: "Nivel inicial del OFP (FL\(level)) y desviación media de temperatura (\(deviation)); la temperatura es la ISA a ese nivel más la desviación",
                why: "El FMGS calcula tiempos y combustible para ese nivel y esa temperatura.",
                affects: "Predicciones de tiempo y combustible, nivel óptimo y máximo, y el punto de descenso (TOD)."))
        }
        if let tropopause = ofp.averageTropopause {
            let rounded = Int((Double(tropopause) / 10).rounded()) * 10
            steps.append(MCDUGuideStep(
                id: "init_tropo", page: "INIT A", field: "TROPO", location: "LSK 6R",
                entries: [GuideEntry(id: "tropo", label: "TROPO", value: "\(rounded)")],
                source: "«Avg tropopause» del OFP",
                why: "Por encima de la tropopausa la temperatura deja de bajar; el valor por defecto (36090 ft) es la atmósfera estándar.",
                affects: "Predicciones a niveles altos.", optional: true))
        }
        if let direction = ofp.averageWindDirection, let speed = ofp.averageWindSpeed, let altitude = ofp.initialAltitude {
            let wind = String(format: "%03d/%03d/%d", direction, speed, altitude / 100)
            steps.append(MCDUGuideStep(
                id: "init_wind", page: "INIT A · WIND", field: "Viento de crucero", location: "INIT A → WIND (o revisión vertical de un punto)",
                entries: [GuideEntry(id: "wind", label: "DIR/VEL/FL", value: wind)],
                source: "Viento medio del OFP («AVG WIND» \(direction)°/\(speed) kt)",
                why: "Sin viento el FMGS supone calma: con viento de cara llegarías más tarde y con menos combustible del que predice.",
                affects: "Hora y combustible previstos en cada punto y en destino.", optional: true))
        }

        // F-PLN
        let departureRunway = ofp.origin.runway ?? ofp.takeoff?.runway
        steps.append(MCDUGuideStep(
            id: "fpln_departure", page: "F-PLN · DEPARTURE", field: "Pista y SID", location: "F-PLN → LSK 1L (\(o)) → DEPARTURE",
            display: [departureRunway.map { "RWY \($0)" }, ofp.sid.map { "SID \($0)" }, ofp.sidTransition.map { "TRANS \($0)" }]
                .compactMap { $0 }.joined(separator: " · "),
            source: "Pista prevista y primer tramo de la ruta del OFP\(ofp.sid.map { " (\($0))" } ?? "")",
            why: "SimBrief elige pista y SID por el viento previsto. Manda la autorización ATC: si te dan otra, carga esa.",
            affects: "Trayectoria inicial y sus restricciones de altitud y velocidad."))
        let route = ofp.routeLegs
        if let start = route.start, !route.legs.isEmpty {
            var entries: [GuideEntry] = []
            for (index, leg) in route.legs.enumerated() {
                entries.append(GuideEntry(id: "via\(index)", label: "VIA", value: leg.via, location: "LSK izquierda"))
                entries.append(GuideEntry(id: "to\(index)", label: "TO", value: leg.to, location: "LSK derecha"))
            }
            steps.append(MCDUGuideStep(
                id: "fpln_route", page: "F-PLN · AIRWAYS", field: "Ruta", location: "Revisión lateral sobre \(start) → AIRWAYS",
                entries: entries,
                display: "Desde \(start): aerovía (VIA) y punto de salida (TO) de cada tramo; DCT es directo. Al terminar, INSERT.",
                source: "Ruta ATC del OFP: «\(ofp.route ?? "")»",
                why: "Es la ruta del plan presentado a ATC: el avión debe volar exactamente esa.",
                affects: "Navegación lateral y distancia total: combustible y tiempo."))
        }
        if let distance = ofp.routeDistance {
            steps.append(MCDUGuideStep(
                id: "fpln_check", page: "F-PLN", field: "Distancia y tiempo totales", location: "Última línea del F-PLN (DEST)",
                display: "OFP: \(distance) NM\(time(ofp.timeEnroute).map { " · \($0) h de vuelo" } ?? "")",
                source: "«DIST» y «TIME» del resumen del OFP",
                why: "Si el total del F-PLN se aleja mucho, falta o sobra un tramo: una discontinuidad, una SID distinta o una aerovía mal metida.",
                affects: nil))
        }
        let steps2 = ofp.stepClimbList
        if !steps2.isEmpty {
            steps.append(MCDUGuideStep(
                id: "fpln_steps", page: "F-PLN · VERT REV", field: "Escalones de ascenso", location: "LSK derecha del punto → STEP ALTS",
                entries: steps2.enumerated().map { index, step in
                    GuideEntry(id: "step\(index)", label: step.fix, value: "\(step.level)")
                },
                source: "«Step climb» del OFP",
                why: "El plan sube de nivel al aligerarse el avión; sin los escalones el FMGS predice todo el vuelo al nivel inicial.",
                affects: "Predicciones de combustible y tiempo.", optional: true))
        }

        // SEC F-PLN
        steps.append(MCDUGuideStep(
            id: "sec_fpln", page: "SEC F-PLN", field: "Plan secundario", location: "SEC F-PLN → COPY ACTIVE",
            display: "Copia el activo y prepara la alternativa más probable (otra pista u otra SID)",
            source: "No está en el OFP: es preparación de la tripulación",
            why: "Si cambia la pista al rodar, activas el secundario en un toque en lugar de reprogramar con prisas.",
            affects: nil, optional: true))

        // RAD NAV
        if let frequency = ofp.takeoff?.ilsFrequency {
            steps.append(MCDUGuideStep(
                id: "radnav_ils", page: "RAD NAV", field: "ILS de la pista de salida", location: "LSK 3L (ILS/FREQ)",
                entries: [GuideEntry(id: "ils", label: "ILS \(ofp.takeoff?.runway ?? "")", value: frequency)],
                source: "Datos de pista del módulo de performance (TLR) del OFP; también en la carta de Navigraph",
                why: "Por si hay que volver tras el despegue: el ILS de la propia pista ya estará sintonizado.",
                affects: "Escalas LS en el PFD y la aproximación de regreso.", optional: true))
        }

        // INIT B / FUEL PRED
        if let zfw = mcduMass(ofp.weights.zeroFuel) {
            steps.append(MCDUGuideStep(
                id: "initb_zfw", page: "INIT B / FUEL PRED", field: "ZFW/ZFWCG", location: "LSK 1R",
                entries: [GuideEntry(id: "zfw", label: "ZFW/ZFWCG", value: "\(zfw)/",
                                     check: GuideCheck(dataref: "toliss_airbus/init/ZFW", kind: .mass, expected: (ofp.weights.zeroFuel ?? 0) / 1000))],
                display: "Teclea el ZFW (\(zfw) \(unit)) y completa el CG tras la barra con el de la hoja de carga (en ToLiss, en el ISCS)",
                source: "«EST ZFW» del bloque de pesos del OFP",
                why: "El OFP trae el ZFW estimado; el definitivo y el centro de gravedad llegan en la hoja de carga. Se meten ahora y se corrigen con la hoja final.",
                affects: "TOW, velocidades características (VLS, F, S, O), nivel máximo y todas las predicciones."))
        }
        let blockFuel = ofp.fuel.block.map { $0 + extraFuel }
        if let block = mcduMass(blockFuel) {
            steps.append(MCDUGuideStep(
                id: "initb_block", page: "INIT B / FUEL PRED", field: "BLOCK", location: "LSK 2R",
                entries: [GuideEntry(id: "block", label: "BLOCK", value: block,
                                     check: GuideCheck(dataref: "toliss_airbus/init/BlockFuel", kind: .mass, expected: (blockFuel ?? 0) / 1000))],
                source: extraFuel > 0
                    ? "«BLOCK» del OFP más el combustible extra que has decidido en el despacho (\(Int(extraFuel.rounded())))"
                    : "«BLOCK» (o «RAMP») del bloque de combustible del OFP",
                why: "Es el combustible total a bordo al empezar a rodar. Comprueba que coincide con el FOB del ECAM.",
                affects: "TOW y combustible previsto en cada punto y en destino."))
        }
        if let taxi = mcduMass(ofp.fuel.taxi) {
            steps.append(MCDUGuideStep(
                id: "initb_taxi", page: "INIT B / FUEL PRED", field: "TAXI", location: "LSK 1L",
                entries: [GuideEntry(id: "taxi", label: "TAXI", value: taxi)],
                source: "«TAXI» del bloque de combustible del OFP",
                why: "Lo que se gasta rodando no está disponible para el vuelo.",
                affects: "TOW = ZFW + BLOCK − TAXI.", optional: true))
        }
        var reserveEntries: [GuideEntry] = []
        if let contingency = mcduMass(ofp.fuel.contingency) { reserveEntries.append(GuideEntry(id: "rte_rsv", label: "RTE RSV", value: contingency, location: "LSK 3L")) }
        if let alternate = mcduMass(ofp.fuel.alternate) { reserveEntries.append(GuideEntry(id: "altn_fuel", label: "ALTN", value: alternate, location: "LSK 4L")) }
        if let final = mcduMass(ofp.fuel.finalReserve) { reserveEntries.append(GuideEntry(id: "final", label: "FINAL", value: final, location: "LSK 5L")) }
        if !reserveEntries.isEmpty {
            steps.append(MCDUGuideStep(
                id: "initb_reserves", page: "INIT B / FUEL PRED", field: "Reservas", location: "LSK 3L · 4L · 5L",
                entries: reserveEntries,
                source: "«CONT», «ALTN» y «FINRES» del bloque de combustible del OFP",
                why: "El FMGS calcula sus propias reservas; meter las del OFP hace que el EXTRA del MCDU sea el del plan.",
                affects: "EXTRA y los avisos de combustible por debajo de la reserva final en vuelo.", optional: true))
        }
        if let tow = mcduMass(ofp.weights.takeoff) {
            steps.append(MCDUGuideStep(
                id: "initb_check", page: "INIT B / FUEL PRED", field: "TOW y TRIP", location: "Lectura de la página",
                display: "OFP: TOW \(tow) \(unit)\(mcduMass(ofp.fuel.trip).map { " · TRIP \($0) \(unit)" } ?? "")",
                source: "«EST TOW» de los pesos y «TRIP» del combustible del OFP",
                why: "Si el TOW o el TRIP del MCDU se alejan de los del OFP, algún dato está mal: ZFW, ruta o nivel.",
                affects: nil))
        }

        // PERF
        if let takeoff = ofp.takeoff, takeoff.v1 != nil || takeoff.vr != nil || takeoff.v2 != nil {
            var entries: [GuideEntry] = []
            if let v1 = takeoff.v1 { entries.append(GuideEntry(id: "v1", label: "V1", value: "\(v1)", location: "LSK 1L", check: GuideCheck(dataref: "toliss_airbus/performance/V1", kind: .number, expected: Double(v1)))) }
            if let vr = takeoff.vr { entries.append(GuideEntry(id: "vr", label: "VR", value: "\(vr)", location: "LSK 2L", check: GuideCheck(dataref: "toliss_airbus/performance/VR", kind: .number, expected: Double(vr)))) }
            if let v2 = takeoff.v2 { entries.append(GuideEntry(id: "v2", label: "V2", value: "\(v2)", location: "LSK 3L", check: GuideCheck(dataref: "toliss_airbus/performance/V2", kind: .number, expected: Double(v2)))) }
            steps.append(MCDUGuideStep(
                id: "perf_speeds", page: "PERF TAKE OFF", field: "V1 · VR · V2", location: "LSK 1L · 2L · 3L",
                entries: entries,
                source: "Módulo de performance (TLR) del OFP, pista \(takeoff.runway)",
                why: "V1 es la decisión de abortar o seguir, VR la rotación y V2 la velocidad segura con un motor parado. El modo SRS del director de vuelo usa V2.",
                affects: "Llamadas del despegue, el SRS y la protección si falla un motor."))
        } else {
            steps.append(MCDUGuideStep(
                id: "perf_speeds", page: "PERF TAKE OFF", field: "V1 · VR · V2", location: "LSK 1L · 2L · 3L",
                display: "El OFP no trae velocidades: actívalas en el módulo de performance de SimBrief (TLR) o calcúlalas con tu herramienta de performance",
                source: "Módulo de performance (TLR) de SimBrief, si está activado",
                why: "V1 es la decisión de abortar o seguir, VR la rotación y V2 la velocidad segura con un motor parado.",
                affects: "Llamadas del despegue, el SRS y la protección si falla un motor."))
        }
        if let transition = ofp.origin.transitionAltitude {
            steps.append(MCDUGuideStep(
                id: "perf_trans", page: "PERF TAKE OFF", field: "TRANS ALT", location: "LSK 4L",
                entries: [GuideEntry(id: "trans", label: "TRANS ALT", value: "\(transition)",
                                     check: GuideCheck(dataref: "toliss_airbus/performance/DeptTrans", kind: .number, expected: Double(transition)))],
                source: "«TRANS ALT» del aeropuerto de salida en el OFP (confírmala en la carta de la SID)",
                why: "Al cruzarla en ascenso se pasa el altímetro a STD (1013).",
                affects: "El aviso de BARO parpadeando cuando toca cambiar a STD."))
        }
        if let takeoff = ofp.takeoff, let flaps = takeoff.flaps, let digit = flaps.first(where: \.isNumber) {
            steps.append(MCDUGuideStep(
                id: "perf_flaps", page: "PERF TAKE OFF", field: "FLAPS/THS", location: "LSK 3R",
                entries: [GuideEntry(id: "flaps", label: "FLAPS/THS", value: "\(digit)/")],
                display: "Flaps \(flaps); completa el THS (UP o DN) según el CG de la hoja de carga",
                source: "TLR del OFP: «FLAP» de la pista \(takeoff.runway)",
                why: "La configuración de despegue tiene que coincidir con la del cálculo de rendimiento; el THS compensa según el centro de gravedad.",
                affects: "La palanca de flaps y la rueda de compensación que comprueba T.O CONFIG."))
        }
        if let flex = ofp.takeoff?.flexTemperature {
            steps.append(MCDUGuideStep(
                id: "perf_flex", page: "PERF TAKE OFF", field: "FLEX TO TEMP", location: "LSK 4R",
                entries: [GuideEntry(id: "flex", label: "FLEX", value: "\(flex)",
                                     check: GuideCheck(dataref: "toliss_airbus/performance/flextemp", kind: .number, expected: Double(flex)))],
                source: "TLR del OFP: «FLEX» de la pista \(ofp.takeoff?.runway ?? "")",
                why: "Con pista de sobra se despega con empuje reducido, como si hiciera esa temperatura: alarga la vida del motor.",
                affects: "El empuje de despegue en FLX: si no se mete, el despegue es con TOGA."))
        }
        if let ci = ofp.costIndex {
            steps.append(MCDUGuideStep(
                id: "perf_phases", page: "PERF CLB · CRZ · DES", field: "Velocidades ECON", location: "PERF → NEXT PHASE",
                display: "Comprueba que son ECON con CI \(ci); deja las velocidades seleccionadas para cuando te las pida ATC",
                source: "Perfiles del OFP: ascenso, crucero «CI \(ci)» y descenso",
                why: "Así el avión vuela las velocidades con las que se calculó el combustible del plan.",
                affects: nil, optional: true))
        }

        // Later in flight
        if let star = ofp.star {
            steps.append(MCDUGuideStep(
                id: "fpln_arrival", page: "F-PLN · ARRIVAL", field: "STAR y aproximación", location: "F-PLN → LSK izquierda (\(d)) → ARRIVAL",
                display: [ofp.destination.runway.map { "RWY \($0)" }, "STAR \(star)", ofp.starTransition.map { "TRANS \($0)" }]
                    .compactMap { $0 }.joined(separator: " · "),
                source: "Último tramo de la ruta del OFP (\(star)) y pista prevista de destino",
                why: "Se carga en crucero, con el ATIS de destino: la pista en servicio puede ser otra que la del plan.",
                affects: "Distancia hasta la pista, punto de descenso y combustible en destino.", optional: true, later: true))
        }
        if let level = ofp.destination.transitionLevel {
            steps.append(MCDUGuideStep(
                id: "perf_appr_trans", page: "PERF APPR", field: "TRANS FL", location: "LSK 4L",
                entries: [GuideEntry(id: "trans_fl", label: "TRANS FL", value: "\(level / 100)")],
                source: "«TRANS LEVEL» del destino en el OFP (el ATIS manda)",
                why: "Al cruzarlo en descenso se pasa del STD al QNH de destino.",
                affects: "El aviso de BARO parpadeando en el descenso.", optional: true, later: true))
        }
        if let frequency = ofp.landingILSFrequency {
            steps.append(MCDUGuideStep(
                id: "radnav_appr", page: "RAD NAV", field: "ILS de llegada", location: "LSK 3L (ILS/FREQ)",
                entries: [GuideEntry(id: "ils_appr", label: "ILS \(ofp.destination.runway ?? "")", value: frequency)],
                source: "Datos de pista de llegada del módulo de performance (TLR); confírmalo en la carta de Navigraph",
                why: "El FMGS lo sintoniza solo al cargar la aproximación; compruébalo contra la carta.",
                affects: "LOC y G/S en el PFD y la captura con APPR.", optional: true, later: true))
        }
        return steps
    }
}

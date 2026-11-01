import Foundation

// Dispatch and departure briefing for one OFP: what the crew decides and notes before the
// flight (extra fuel, MEL items, NOTAMs read, ATIS, clearance, engine-out procedure, SID
// constraints, walkaround), plus the helpers that read an ATIS, size the duty period and check
// the SID constraints in flight. Stored per OFP on the device.

public struct DispatchState: Codable, Sendable, Equatable {
    public var requestID: String?
    /// Fuel the captain adds over the OFP, kg, and why.
    public var extraFuelKg: Double = 0
    public var extraFuelReason: String = ""
    /// Ids of the simulated MEL items deferred for this flight.
    public var melItems: [String] = []
    /// NOTAM texts marked as read (by their first line).
    public var notamsRead: [String] = []
    public var atisText: String = ""
    public var clearance = DepartureClearance()
    public var engineOutProcedure: String = ""
    public var accelerationAltitude: Int?
    public var threats: String = ""
    public var sidConstraints: [AltitudeConstraint] = []
    public var walkaroundDone: [String] = []
    /// When the dispatch summary and the departure briefing were done.
    public var dispatchSigned: Date?
    public var departureBriefed: Date?
    /// Sectors planned today (for the duty period) and minutes from report to off-blocks.
    public var sectorsToday: Int = 2
    public var reportMinutesBeforeOffBlocks: Int = 60
    /// Ground and departure (optional so saved states still load): de-icing, single-engine
    /// taxi-out, and the line-up items done.
    public var deicing: DeicingRecord?
    public var singleEngineTaxi: Bool?
    public var lineupDone: [String]?

    public init(requestID: String? = nil) {
        self.requestID = requestID
    }
}

public struct DepartureClearance: Codable, Sendable, Equatable {
    public var sid: String = ""
    public var runway: String = ""
    /// Feet, or a flight level ×100.
    public var initialAltitude: Int?
    public var squawk: String = ""
    public var departureFrequency: String = ""

    public init() {}

    /// A transponder code has four octal digits.
    public var isSquawkValid: Bool {
        squawk.count == 4 && squawk.allSatisfy { ("0"..."7").contains($0) }
    }
}

// MARK: ATIS

/// What the ATIS says, as far as a plain text can be read.
public struct ATISInfo: Sendable, Equatable {
    public var letter: String?
    public var runway: String?
    /// Hectopascals.
    public var qnh: Int?
    public var windDirection: Int?
    public var windSpeed: Int?
    public var gust: Int?
    public var temperature: Int?
    public var dewpoint: Int?
    public var transitionLevel: Int?

    public var isEmpty: Bool {
        letter == nil && runway == nil && qnh == nil && windSpeed == nil && temperature == nil && transitionLevel == nil
    }

    /// Reads a voice-style or METAR-style ATIS: "INFORMATION B", "RWY 36L", "QNH 1013" or
    /// "Q1013" or "A2992", "WIND 340/10" or "34010G20KT", "TEMPERATURE 12" or "12/M02",
    /// "TRANSITION LEVEL 70" or "TL 70".
    public static func parse(_ text: String) -> ATISInfo {
        let t = " " + text.uppercased().replacingOccurrences(of: "\n", with: " ") + " "
        var info = ATISInfo()
        info.letter = letter(in: t)
        info.runway = first(#"(?:RWY|RUNWAY|RUNWAYS)\s*(?:IN USE\s*)?(\d{2}[LRC]?)\b"#, in: t)
        if let qnh = first(#"(?:QNH\s*|\sQ)(\d{3,4})\b"#, in: t).flatMap(Int.init) {
            info.qnh = qnh
        } else if let inHg = first(#"\sA(\d{4})\b"#, in: t).flatMap(Double.init) {
            info.qnh = Int((inHg / 100 * 33.8639).rounded())
        }
        if let groups = groups(#"\s(\d{3}|VRB)(\d{2,3})(?:G(\d{2,3}))?KT\b"#, in: t) {
            info.windDirection = groups[0].flatMap { Int($0) }
            info.windSpeed = groups[1].flatMap { Int($0) }
            info.gust = groups[2].flatMap { Int($0) }
        } else if let groups = groups(#"WIND\s+(\d{3})\s*(?:/|DEGREES?|AT)\s*(\d{1,3})"#, in: t) {
            info.windDirection = groups[0].flatMap { Int($0) }
            info.windSpeed = groups[1].flatMap { Int($0) }
        }
        if let groups = groups(#"\s(M?\d{2})/(M?\d{2})\s"#, in: t) {
            info.temperature = celsius(groups[0])
            info.dewpoint = celsius(groups[1])
        } else if let value = first(#"(?:TEMPERATURE|TEMP)\s+(MINUS\s+\d{1,2}|[M-]?\d{1,2})"#, in: t) {
            info.temperature = celsius(value)
        }
        info.transitionLevel = first(#"\b(?:TRANSITION LEVEL|TRANS LEVEL|TRL|TL)\s*(?:FL\s*)?(\d{2,3})\b"#, in: t).flatMap(Int.init)
        return info
    }

    static let phonetic = ["ALFA", "ALPHA", "BRAVO", "CHARLIE", "DELTA", "ECHO", "FOXTROT", "GOLF", "HOTEL", "INDIA",
                           "JULIET", "JULIETT", "KILO", "LIMA", "MIKE", "NOVEMBER", "OSCAR", "PAPA", "QUEBEC", "ROMEO",
                           "SIERRA", "TANGO", "UNIFORM", "VICTOR", "WHISKEY", "WHISKY", "XRAY", "YANKEE", "ZULU"]

    /// The information letter after INFORMATION, INFO or ATIS, as a letter or a phonetic word.
    private static func letter(in text: String) -> String? {
        // The word is captured in a lookahead so "ATIS INFO K" can still match at "INFO".
        guard let regex = try? NSRegularExpression(pattern: #"(?:INFORMATION|INFO|ATIS)\s+(?=([A-Z]+)\b)"#) else { return nil }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let word = String(text[range])
            if word.count == 1 { return word }
            if phonetic.contains(word) { return String(word.prefix(1)) }
        }
        return nil
    }

    private static func celsius(_ text: String?) -> Int? {
        guard var value = text?.trimmingCharacters(in: .whitespaces) else { return nil }
        var negative = false
        if value.hasPrefix("MINUS") { negative = true; value = String(value.dropFirst(5)).trimmingCharacters(in: .whitespaces) }
        if value.hasPrefix("M") { negative = true; value = String(value.dropFirst()) }
        return Int(value).map { negative ? -$0 : $0 }
    }

    private static func first(_ pattern: String, in text: String) -> String? {
        groups(pattern, in: text)?.first ?? nil
    }

    /// Capture groups of the first match (nil for groups that did not take part).
    private static func groups(_ pattern: String, in text: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
    }
}

// MARK: Weather

public enum WeatherCategory: String, Sendable, CaseIterable {
    case vfr, mvfr, ifr, lifr

    public var title: String {
        switch self {
        case .vfr: return "VFR"
        case .mvfr: return "VFR marginal"
        case .ifr: return "IFR"
        case .lifr: return "IFR bajo"
        }
    }

    /// For destination and alternate planning.
    public var advice: String? {
        switch self {
        case .vfr, .mvfr: return nil
        case .ifr: return "Instrumental: prepara la aproximación de precisión y revisa los mínimos."
        case .lifr: return "Techo o visibilidad muy bajos: comprueba que la previsión está por encima de los mínimos de planificación y que el alterno vale."
        }
    }
}

// MARK: MEL

/// A simulated Minimum Equipment List item: what is inoperative and what it changes.
public struct MELItem: Sendable, Identifiable, Hashable {
    public let id: String
    public let ata: String
    public let title: String
    public let consequences: [String]

    /// Simplified A320 examples for training; the real MEL is the operator's document.
    public static let catalog: [MELItem] = [
        MELItem(id: "apu", ata: "49-10", title: "APU inoperativo",
                consequences: ["En tierra, corriente con GPU y aire acondicionado de tierra (AIRE LP)",
                               "Arranque del primer motor con carro de aire (AIRE HP) y el segundo con X BLEED",
                               "Sin respaldo del APU si falla un generador en vuelo"]),
        MELItem(id: "pack", ata: "21-51", title: "Un pack inoperativo",
                consequences: ["Nivel máximo FL315", "PACK FLOW en HI con el pack que queda",
                               "Más consumo si el plan iba más alto: revisa el combustible"]),
        MELItem(id: "gen", ata: "24-22", title: "Un generador (IDG) inoperativo",
                consequences: ["APU GEN disponible y en marcha todo el vuelo", "Revisa el combustible extra del APU"]),
        MELItem(id: "ap", ata: "22-11", title: "Un piloto automático inoperativo",
                consequences: ["Sin CAT 3 DUAL: mínimos más altos en baja visibilidad", "Usa el otro AP"]),
        MELItem(id: "wxr", ata: "34-41", title: "Radar meteorológico inoperativo",
                consequences: ["No despachar con tormentas previstas en la ruta o en destino", "Revisa SIGMET y TAF"]),
        MELItem(id: "reverser", ata: "78-30", title: "Un reversor desactivado",
                consequences: ["Mayor distancia de aterrizaje: revisa la pista en mojado o contaminada",
                               "Autobrake MED en pistas cortas"]),
        MELItem(id: "landing_light", ata: "33-42", title: "Una luz de aterrizaje inoperativa",
                consequences: ["Vuelo nocturno permitido con la otra; en algunas compañías, solo de día"]),
        MELItem(id: "fuel_pump", ata: "28-21", title: "Una bomba de ala inoperativa",
                consequences: ["Alimentación por la otra bomba del ala", "Vigila el desequilibrio de combustible"]),
    ]
}

// MARK: Duty period

/// EASA ORO.FTL.205 maximum basic daily flight duty period for an acclimatised crew,
/// simplified: by the local reporting time, 30 minutes less from the third sector on.
public enum DutyPeriod {
    /// Maximum FDP in minutes for a report time (minutes after local midnight) and sectors.
    public static func maximumMinutes(reportMinuteOfDay: Int, sectors: Int) -> Int {
        let m = reportMinuteOfDay
        let base: Int
        switch m {
        case 300..<315: base = 12 * 60
        case 315..<330: base = 12 * 60 + 15
        case 330..<345: base = 12 * 60 + 30
        case 345..<360: base = 12 * 60 + 45
        case 360..<810: base = 13 * 60
        case 810..<1020: base = 13 * 60 - ((m - 810) / 30 + 1) * 15
        default: base = 11 * 60
        }
        let reduction = max(0, sectors - 2) * 30
        return max(9 * 60, base - reduction)
    }
}

// MARK: SID constraints

/// A constraint from the departure chart, noted in the briefing.
public struct AltitudeConstraint: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case at, atOrAbove, atOrBelow

        public var symbol: String {
            switch self {
            case .at: return "="
            case .atOrAbove: return "A"
            case .atOrBelow: return "B"
            }
        }
    }

    public var id: UUID
    public var fix: String
    public var kind: Kind
    public var altitude: Int
    /// Maximum speed at the fix, kt.
    public var speed: Int?

    public init(id: UUID = UUID(), fix: String, kind: Kind, altitude: Int, speed: Int? = nil) {
        self.id = id
        self.fix = fix
        self.kind = kind
        self.altitude = altitude
        self.speed = speed
    }

    public var text: String {
        let altitudeText: String
        switch kind {
        case .at: altitudeText = "\(altitude) ft"
        case .atOrAbove: altitudeText = "A\(altitude) (o más)"
        case .atOrBelow: altitudeText = "B\(altitude) (o menos)"
        }
        return "\(fix) \(altitudeText)" + (speed.map { " · máx \($0) kt" } ?? "")
    }

    /// What was wrong when crossing the fix (empty when within the constraint). Altitudes
    /// have 300 ft of margin, speeds 10 kt.
    public func violations(altitude crossing: Double, speed ias: Double?) -> [String] {
        var problems: [String] = []
        let a = Double(altitude)
        switch kind {
        case .at where abs(crossing - a) > 300:
            problems.append("\(Int(crossing.rounded())) ft en lugar de \(altitude)")
        case .atOrAbove where crossing < a - 300:
            problems.append("\(Int(crossing.rounded())) ft, por debajo de \(altitude)")
        case .atOrBelow where crossing > a + 300:
            problems.append("\(Int(crossing.rounded())) ft, por encima de \(altitude)")
        default:
            break
        }
        if let limit = speed, let ias, ias > Double(limit) + 10 {
            problems.append("\(Int(ias.rounded())) kt con límite \(limit)")
        }
        return problems
    }
}

/// Catches a level bust: the aircraft captured the altitude selected on the FCU and then left
/// it by more than 300 ft without a new altitude being selected.
public struct LevelBustMonitor: Sendable {
    private var captured: Double?
    private var capturedSince: Date?
    private var warned = false

    public init() {}

    /// Returns the deviation (ft) once when a captured altitude is lost.
    public mutating func update(altitude: Double, selected: Double, at date: Date) -> Double? {
        if let target = captured, target != selected {
            captured = nil
            capturedSince = nil
            warned = false
        }
        if abs(altitude - selected) <= 200 {
            if capturedSince == nil { capturedSince = date }
            if let since = capturedSince, date.timeIntervalSince(since) >= 5 { captured = selected }
            warned = false
            return nil
        }
        capturedSince = nil
        guard captured != nil, !warned, abs(altitude - selected) > 300 else { return nil }
        warned = true
        return altitude - selected
    }
}

// MARK: Walkaround

public struct WalkaroundPoint: Sendable, Identifiable, Hashable {
    public let id: String
    public let area: String
    public let checks: String

    /// The exterior inspection, clockwise from the nose, as airline walkarounds go.
    public static let route: [WalkaroundPoint] = [
        WalkaroundPoint(id: "nose", area: "Morro", checks: "Radomo sin daños; sondas pitot, de ángulo de ataque y de temperatura sin fundas ni daños; antenas"),
        WalkaroundPoint(id: "nose_gear", area: "Tren de morro", checks: "Neumáticos y presión, amortiguador, sin fugas, pasador de remolque y del tren retirados, luces"),
        WalkaroundPoint(id: "left_fuselage", area: "Fuselaje izquierdo", checks: "Tomas estáticas limpias, antenas, puertas y escotillas cerradas salvo las de servicio"),
        WalkaroundPoint(id: "left_engine", area: "Motor 1", checks: "Toma de aire y álabes del fan, capós cerrados y asegurados, reversa guardada, sin fugas"),
        WalkaroundPoint(id: "left_wing", area: "Ala izquierda", checks: "Borde de ataque y slats, luces de navegación y estroboscópica, descargadores estáticos, flaps y alerones, sin hielo"),
        WalkaroundPoint(id: "left_main_gear", area: "Tren principal izquierdo", checks: "Neumáticos, indicadores de desgaste de frenos, sin fugas hidráulicas, pasador retirado"),
        WalkaroundPoint(id: "tail", area: "Cola", checks: "Estabilizador y timones, escape y toma del APU, luz de la cola, sin daños por golpe de cola"),
        WalkaroundPoint(id: "right_main_gear", area: "Tren principal derecho", checks: "Neumáticos, frenos, fugas, pasador retirado"),
        WalkaroundPoint(id: "right_wing", area: "Ala derecha", checks: "Borde de ataque, luces, superficies de mando, drenajes de combustible, sin hielo"),
        WalkaroundPoint(id: "right_engine", area: "Motor 2", checks: "Toma y fan, capós, reversa, sin fugas"),
        WalkaroundPoint(id: "right_fuselage", area: "Fuselaje derecho", checks: "Tomas estáticas, puertas y bodegas, panel de repostaje cerrado al terminar"),
        WalkaroundPoint(id: "ground", area: "Alrededor", checks: "Calzos, conos, objetos sueltos (FOD), vehículos de handling retirados de la trayectoria del push"),
    ]
}

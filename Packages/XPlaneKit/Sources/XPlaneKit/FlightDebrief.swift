import Foundation

// Post-flight report in the spirit of an airline's flight data monitoring (FOQA/FDM): a trace of
// the flight and the events an analyst would flag, each with when it happened and how serious it
// was. Thresholds are typical FDM levels for the A320, not those of a particular operator.

/// One reading of the flight, kept every few seconds.
public struct FlightSample: Codable, Sendable, Equatable {
    /// Seconds since the recording started.
    public var time: TimeInterval
    public var altitude: Double
    public var heightAboveField: Double
    public var ias: Double
    public var groundspeed: Double
    public var verticalSpeed: Double
    public var bank: Double
    public var pitch: Double
    public var onGround: Bool
    public var latitude: Double
    public var longitude: Double

    public init(time: TimeInterval, altitude: Double, heightAboveField: Double, ias: Double, groundspeed: Double,
                verticalSpeed: Double, bank: Double, pitch: Double, onGround: Bool, latitude: Double, longitude: Double) {
        self.time = time
        self.altitude = altitude
        self.heightAboveField = heightAboveField
        self.ias = ias
        self.groundspeed = groundspeed
        self.verticalSpeed = verticalSpeed
        self.bank = bank
        self.pitch = pitch
        self.onGround = onGround
        self.latitude = latitude
        self.longitude = longitude
    }
}

public struct FlightEvent: Codable, Sendable, Equatable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case unstableApproach
        case highSinkRateLow
        case excessiveBank
        case tailStrikeRisk
        case hardLanding
        case firmLanding
        case speedBelowFL100
        case longFlare
        case fastTaxi

        public var title: String {
            switch self {
            case .unstableApproach: return "Aproximación no estabilizada"
            case .highSinkRateLow: return "Régimen de descenso alto cerca del suelo"
            case .excessiveBank: return "Alabeo excesivo"
            case .tailStrikeRisk: return "Riesgo de golpe de cola"
            case .hardLanding: return "Toma dura"
            case .firmLanding: return "Toma firme"
            case .speedBelowFL100: return "Más de 250 kt bajo FL100"
            case .longFlare: return "Flotada larga"
            case .fastTaxi: return "Rodaje rápido"
            }
        }
    }

    public enum Severity: Int, Codable, Sendable, Comparable {
        case low = 1, medium = 2, high = 3

        public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

        public var title: String {
            switch self {
            case .low: return "Leve"
            case .medium: return "Media"
            case .high: return "Alta"
            }
        }

        /// Points taken off the score of 100.
        public var penalty: Int {
            switch self {
            case .low: return 3
            case .medium: return 8
            case .high: return 20
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var severity: Severity
    /// Seconds since the recording started.
    public var time: TimeInterval
    /// What was measured, e.g. "38° de alabeo a 2400 ft".
    public var detail: String

    public init(id: UUID = UUID(), kind: Kind, severity: Severity, time: TimeInterval, detail: String) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.time = time
        self.detail = detail
    }
}

/// A finished flight: trace, events and score.
public struct FlightDebrief: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var start: Date
    public var end: Date
    public var origin: String?
    public var destination: String?
    public var flightNumber: String?
    public var samples: [FlightSample]
    public var events: [FlightEvent]
    public var landingRate: Int?
    public var landingG: Double?

    public init(id: UUID = UUID(), start: Date, end: Date, origin: String? = nil, destination: String? = nil,
                flightNumber: String? = nil, samples: [FlightSample], events: [FlightEvent],
                landingRate: Int? = nil, landingG: Double? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.origin = origin
        self.destination = destination
        self.flightNumber = flightNumber
        self.samples = samples
        self.events = events
        self.landingRate = landingRate
        self.landingG = landingG
    }

    /// 100 less the penalty of each event, never below 0.
    public var score: Int {
        max(0, 100 - events.reduce(0) { $0 + $1.severity.penalty })
    }

    public var grade: String {
        switch score {
        case 90...: return "Excelente"
        case 75..<90: return "Bueno"
        case 50..<75: return "Mejorable"
        default: return "Revisar"
        }
    }

    public var title: String {
        let route = [origin, destination].compactMap { $0 }.joined(separator: "→")
        return [flightNumber, route.isEmpty ? nil : route].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// Watches the flight one reading at a time and flags each event once per occurrence: a limit
/// held for a moment raises it, and it can be raised again only after the aircraft is back
/// within limits.
public struct FlightEventDetector: Sendable {
    public struct Reading: Sendable, Equatable {
        public var time: TimeInterval
        public var altitude: Double
        public var heightAboveField: Double
        public var ias: Double
        public var groundspeed: Double
        public var verticalSpeed: Double
        public var bank: Double
        public var pitch: Double
        public var onGround: Bool
        public var radioAltitude: Double

        public init(time: TimeInterval, altitude: Double, heightAboveField: Double, ias: Double, groundspeed: Double,
                    verticalSpeed: Double, bank: Double, pitch: Double, onGround: Bool, radioAltitude: Double) {
            self.time = time
            self.altitude = altitude
            self.heightAboveField = heightAboveField
            self.ias = ias
            self.groundspeed = groundspeed
            self.verticalSpeed = verticalSpeed
            self.bank = bank
            self.pitch = pitch
            self.onGround = onGround
            self.radioAltitude = radioAltitude
        }
    }

    /// Seconds a limit must hold before it counts.
    public static let persistence: TimeInterval = 2

    private var exceededSince: [FlightEvent.Kind: TimeInterval] = [:]
    private var active: Set<FlightEvent.Kind> = []
    private var previous: Reading?
    /// Time the aircraft last crossed 50 ft on the way down, for the flare.
    private var fiftyFeetAt: TimeInterval?
    /// Ground roll after a landing or before a take-off: not taxiing.
    private var lastAirborne: TimeInterval?

    /// Pitch at which the tail touches with the gear compressed (11.7° on the A320).
    public var tailStrikePitch: Double

    public init(tailStrikePitch: Double = 11.7) {
        self.tailStrikePitch = tailStrikePitch
    }

    public mutating func update(_ now: Reading) -> [FlightEvent] {
        defer { previous = now }
        var events: [FlightEvent] = []

        if !now.onGround { lastAirborne = now.time }
        if let before = previous, !now.onGround, before.radioAltitude > 50, now.radioAltitude <= 50, now.verticalSpeed < 0 {
            fiftyFeetAt = now.time
        }
        if let before = previous, now.onGround, !before.onGround, let fifty = fiftyFeetAt {
            let flare = now.time - fifty
            if flare > 10 {
                events.append(FlightEvent(kind: .longFlare, severity: flare > 14 ? .medium : .low, time: now.time,
                                          detail: String(format: "%.0f s desde 50 ft hasta la toma", flare)))
            }
            fiftyFeetAt = nil
        }

        func check(_ kind: FlightEvent.Kind, _ exceeded: Bool, severity: () -> FlightEvent.Severity, detail: () -> String) {
            guard exceeded else {
                exceededSince[kind] = nil
                active.remove(kind)
                return
            }
            let since = exceededSince[kind] ?? now.time
            exceededSince[kind] = since
            if now.time - since >= Self.persistence, active.insert(kind).inserted {
                events.append(FlightEvent(kind: kind, severity: severity(), time: now.time, detail: detail()))
            }
        }

        let airborne = !now.onGround
        let height = now.heightAboveField

        check(.highSinkRateLow, airborne && height < 1000 && height > 50 && now.verticalSpeed < -1200,
              severity: { now.verticalSpeed < -1500 ? .high : .medium },
              detail: { "\(Int(-now.verticalSpeed)) ft/min a \(Int(height)) ft" })
        // Wings close to level near the ground; normal manoeuvring limit (33°) above.
        check(.excessiveBank, airborne && abs(now.bank) > (height < 400 ? 10 : 33),
              severity: { abs(now.bank) > 40 || height < 400 ? .high : .medium },
              detail: { "\(Int(abs(now.bank).rounded()))° de alabeo a \(Int(height)) ft" })
        // The tail touches at `tailStrikePitch` with the gear compressed (A320 11.7°: warns above
        // 10°, high above 11°). Other aircraft keep the same proportion of their own limit
        // (A340-600 9.5°: 8.1° and 8.9°).
        let scale = tailStrikePitch / 11.7
        let warnPitch = scale * 10
        let highPitch = scale * 11
        check(.tailStrikeRisk, now.radioAltitude < 15 && now.pitch > warnPitch && now.ias > 80,
              severity: { now.pitch > highPitch ? .high : .medium },
              detail: { String(format: "%.1f° de cabeceo a %.0f ft", now.pitch, now.radioAltitude) })
        check(.speedBelowFL100, airborne && now.altitude < 9_800 && height > 2_500 && now.ias > 260,
              severity: { now.ias > 280 ? .medium : .low },
              detail: { "\(Int(now.ias)) kt a \(Int(now.altitude)) ft" })
        let rolling = lastAirborne.map { now.time - $0 < 120 } ?? false
        check(.fastTaxi, now.onGround && !rolling && now.groundspeed > 30 && now.ias < 60,
              severity: { now.groundspeed > 40 ? .medium : .low },
              detail: { "\(Int(now.groundspeed)) kt en rodaje" })
        return events
    }

    /// The touchdown as the landing detector measured it.
    public static func landing(rate: Int, g: Double, at time: TimeInterval) -> FlightEvent? {
        if rate > 600 || g > 2.6 {
            return FlightEvent(kind: .hardLanding, severity: .high, time: time,
                               detail: String(format: "%d ft/min · %.2f g", rate, g))
        }
        if rate > 400 || g > 1.8 {
            return FlightEvent(kind: .firmLanding, severity: .low, time: time,
                               detail: String(format: "%d ft/min · %.2f g", rate, g))
        }
        return nil
    }

    /// A gate of the stabilised approach monitor that was not stable.
    public static func unstable(gate: Int, failures: [String], at time: TimeInterval) -> FlightEvent {
        FlightEvent(kind: .unstableApproach, severity: gate <= 500 ? .high : .medium, time: time,
                    detail: "\(gate) ft: \(failures.joined(separator: ", "))")
    }
}

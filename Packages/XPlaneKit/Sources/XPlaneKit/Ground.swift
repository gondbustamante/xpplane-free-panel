import Foundation

// Ground and departure operations beyond the turnaround: A-CDM times, de-icing holdover,
// taxi (single-engine), plus the in-flight checks that were missing: cross-track navigation
// check, wind in the top of descent and an approximate landing distance.

// MARK: A-CDM (3.1)

/// Airport CDM: the crew commits to a target off-blocks time (TOBT) and the airport gives a
/// target start-up approval time (TSAT). Start-up is expected within TSAT ±5 minutes, and the
/// TOBT has to be updated as soon as the aircraft will not be ready within 5 minutes of it.
public struct ACDMTimes: Codable, Sendable, Equatable {
    public var tobt: Date
    public var tsat: Date?
    /// Expected taxi-out time, minutes (EXOT).
    public var taxiMinutes: Double

    public init(tobt: Date, tsat: Date? = nil, taxiMinutes: Double = 10) {
        self.tobt = tobt
        self.tsat = tsat
        self.taxiMinutes = taxiMinutes
    }

    public static let tolerance: TimeInterval = 5 * 60

    /// TSAT, or the TOBT until the airport issues one.
    public var startup: Date { tsat ?? tobt }
    /// Target take-off time: start-up plus taxi.
    public var ttot: Date { startup.addingTimeInterval(taxiMinutes * 60) }
    public var startupWindow: ClosedRange<Date> {
        startup.addingTimeInterval(-Self.tolerance)...startup.addingTimeInterval(Self.tolerance)
    }

    public enum Status: Equatable, Sendable {
        /// Before the start-up window.
        case waiting(minutes: Int)
        case window(minutesLeft: Int)
        /// Past the window: the TSAT is lost and a new TOBT is needed.
        case missed
        /// Ready later than TOBT + 5: update the TOBT now (minutes late).
        case updateTOBT(Int)
    }

    /// Where the flight stands at `date`, given when it expects to be ready to push.
    public func status(at date: Date, expectedReady: Date?) -> Status {
        if let ready = expectedReady, ready > tobt.addingTimeInterval(Self.tolerance), date < startupWindow.upperBound {
            return .updateTOBT(Int((ready.timeIntervalSince(tobt) / 60).rounded()))
        }
        if date < startupWindow.lowerBound {
            return .waiting(minutes: Int((startupWindow.lowerBound.timeIntervalSince(date) / 60).rounded(.up)))
        }
        if date <= startupWindow.upperBound {
            return .window(minutesLeft: Int((startupWindow.upperBound.timeIntervalSince(date) / 60).rounded(.down)))
        }
        return .missed
    }
}

// MARK: De-icing (3.4)

/// Training holdover times: how long a de-icing/anti-icing fluid protects the aircraft.
/// Simplified from the generic tables; the real values come from the season's FAA/Transport
/// Canada tables for the exact fluid brand.
public enum Deicing {
    public enum Fluid: String, Codable, Sendable, CaseIterable {
        /// Heated, thin: de-icing only, short protection.
        case typeI
        /// Thickened: anti-icing, long protection.
        case typeIV

        public var title: String { self == .typeI ? "Tipo I (naranja)" : "Tipo IV (verde)" }
    }

    public enum Condition: String, Codable, Sendable, CaseIterable {
        case frost, freezingFog, lightSnow, moderateSnow, freezingDrizzle, lightFreezingRain

        public var title: String {
            switch self {
            case .frost: return "Escarcha"
            case .freezingFog: return "Niebla engelante"
            case .lightSnow: return "Nieve ligera"
            case .moderateSnow: return "Nieve moderada"
            case .freezingDrizzle: return "Llovizna engelante"
            case .lightFreezingRain: return "Lluvia engelante ligera"
            }
        }
    }

    /// Holdover time in minutes (shortest...longest), or nil when the fluid gives no protection
    /// there (below its lowest operational use temperature or in that precipitation).
    public static func holdover(fluid: Fluid, condition: Condition, temperature: Int) -> ClosedRange<Int>? {
        let cold = temperature < -3
        if temperature < (fluid == .typeI ? -30 : -25) { return nil }
        switch fluid {
        case .typeI:
            switch condition {
            case .frost: return 45...45
            case .freezingFog: return cold ? 8...13 : 11...17
            case .lightSnow: return cold ? 8...13 : 11...18
            case .moderateSnow: return cold ? 5...8 : 6...11
            case .freezingDrizzle: return cold ? 4...7 : 5...9
            case .lightFreezingRain: return cold ? 2...5 : 2...5
            }
        case .typeIV:
            switch condition {
            case .frost: return cold ? 120...120 : 360...360
            case .freezingFog: return cold ? 40...100 : 65...135
            case .lightSnow: return cold ? 30...60 : 45...75
            case .moderateSnow: return cold ? 15...30 : 25...45
            case .freezingDrizzle: return cold ? 20...50 : 40...70
            case .lightFreezingRain: return cold ? 10...20 : 25...40
            }
        }
    }

    /// Minutes left of protection from the start of the final step.
    public static func remaining(start: Date, holdover: ClosedRange<Int>, at date: Date) -> (toMinimum: Int, toMaximum: Int) {
        let elapsed = date.timeIntervalSince(start) / 60
        return (Int((Double(holdover.lowerBound) - elapsed).rounded(.down)), Int((Double(holdover.upperBound) - elapsed).rounded(.down)))
    }
}

/// A de-icing done at the gate or the pad.
public struct DeicingRecord: Codable, Sendable, Equatable {
    public var fluid: Deicing.Fluid
    public var condition: Deicing.Condition
    public var temperature: Int
    /// Start of the final (anti-icing) step: the holdover counts from here.
    public var start: Date

    public init(fluid: Deicing.Fluid, condition: Deicing.Condition, temperature: Int, start: Date) {
        self.fluid = fluid
        self.condition = condition
        self.temperature = temperature
        self.start = start
    }

    public var holdover: ClosedRange<Int>? {
        Deicing.holdover(fluid: fluid, condition: condition, temperature: temperature)
    }
}

// MARK: Taxi (3.3)

public enum Taxi {
    /// Minutes the second engine needs running before take-off thrust (warm-up), typical CFM/IAE.
    public static let warmUpMinutes = 3.0
    /// Minutes an engine runs at idle after landing before shutting it down (cool-down).
    public static let coolDownMinutes = 3.0
    /// A320 idle burn on the ground, kg per minute per engine (about 5 kg/min each).
    public static let idleBurnPerEngine = 5.0

    /// When to start the second engine on a single-engine taxi: warm-up plus the start itself
    /// (about 2 minutes) before the expected take-off.
    public static func secondEngineStart(takeoff: Date) -> Date {
        takeoff.addingTimeInterval(-(warmUpMinutes + 2) * 60)
    }

    /// Fuel saved taxiing on one engine for `minutes` instead of two, kg.
    public static func singleEngineSaving(minutes: Double) -> Double {
        max(0, minutes - warmUpMinutes - 2) * idleBurnPerEngine
    }
}

// MARK: Navigation check (5.2)

extension Geo {
    /// Cross-track distance of a position from the great circle A→B, NM (positive: right of track).
    public static func crossTrack(latitude: Double, longitude: Double,
                                  from a: (lat: Double, lon: Double), to b: (lat: Double, lon: Double)) -> Double {
        let r = 3440.065
        func rad(_ d: Double) -> Double { d * .pi / 180 }
        func bearing(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
            let y = sin(rad(lon2 - lon1)) * cos(rad(lat2))
            let x = cos(rad(lat1)) * sin(rad(lat2)) - sin(rad(lat1)) * cos(rad(lat2)) * cos(rad(lon2 - lon1))
            return atan2(y, x)
        }
        let d13 = distance(a.lat, a.lon, latitude, longitude) / r
        let difference = bearing(a.lat, a.lon, latitude, longitude) - bearing(a.lat, a.lon, b.lat, b.lon)
        return asin(sin(d13) * sin(difference)) * r
    }
}

// MARK: Descent with wind (6.1)

extension DescentProfile {
    /// Average descent rate used for the time of the descent, ft/min.
    public static let averageDescentRate = 2200.0

    /// Extra miles for the wind: the along-track component (positive tailwind) blows the aircraft
    /// during the descent; the wind weakens lower down, so about 60 % of it counts.
    public static func windCorrection(altitude: Double, destinationElevation: Double, tailwind: Double) -> Double {
        let minutes = max(0, altitude - destinationElevation) / averageDescentRate
        return tailwind * 0.6 * minutes / 60
    }
}

// MARK: Landing distance (6.5)

/// Rough A320 landing distance from 50 ft over the threshold to a stop, for training. Not an
/// approved performance calculation: the airline's tables or the EFB give the real one.
public enum LandingDistance {
    public enum Braking: String, Codable, Sendable, CaseIterable {
        case low, medium, maxManual

        public var title: String {
            switch self {
            case .low: return "Autobrake LO"
            case .medium: return "Autobrake MED"
            case .maxManual: return "Frenada manual máxima"
            }
        }
        /// Target deceleration, m/s².
        var deceleration: Double {
            switch self {
            case .low: return 1.7
            case .medium: return 3.0
            case .maxManual: return 4.5
            }
        }
    }

    public enum Surface: String, Codable, Sendable, CaseIterable {
        case dry, wet, compactedSnow, standingWater

        public var title: String {
            switch self {
            case .dry: return "Seca"
            case .wet: return "Mojada"
            case .compactedSnow: return "Nieve compacta"
            case .standingWater: return "Agua (más de 3 mm)"
            }
        }
        /// Deceleration the surface allows, m/s².
        var maximumDeceleration: Double {
            switch self {
            case .dry: return 4.5
            case .wet: return 3.0
            case .compactedSnow: return 2.0
            case .standingWater: return 1.5
            }
        }

        public init(simBrief text: String?) {
            switch text?.lowercased() {
            case "wet"?: self = .wet
            case let value? where value.contains("snow") || value.contains("ice"): self = .compactedSnow
            case let value? where value.contains("water") || value.contains("slush"): self = .standingWater
            default: self = .dry
            }
        }
    }

    /// Approach speed at a landing weight in CONF FULL, kt (about VLS + 5).
    public static func approachSpeed(weightKg: Double) -> Double {
        132 * sqrt(max(40_000, weightKg) / 64_000)
    }

    /// Distance in metres. `headwind` positive, tailwind negative (knots).
    public static func estimate(weightKg: Double, elevationFt: Double, headwind: Double,
                                braking: Braking, surface: Surface) -> Double {
        let ias = approachSpeed(weightKg: weightKg)
        let tas = ias * (1 + 0.02 * max(0, elevationFt) / 1000)
        // Regulations count half the headwind and 150 % of the tailwind.
        let wind = headwind >= 0 ? headwind * 0.5 : headwind * 1.5
        let groundspeed = max(60, tas - wind) * 0.514444
        let touchdown = groundspeed * 0.97
        let air = groundspeed * 6            // 50 ft to touchdown, about 6 s
        let transition = touchdown * 2       // spoilers and brakes coming in
        let decel = min(braking.deceleration, surface.maximumDeceleration)
        return air + transition + touchdown * touchdown / (2 * decel)
    }

    /// In-flight assessment: the estimate plus the 15 % EASA margin.
    public static func factored(_ distance: Double) -> Double { distance * 1.15 }
}

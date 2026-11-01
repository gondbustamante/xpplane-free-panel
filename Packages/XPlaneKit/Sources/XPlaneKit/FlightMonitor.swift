import Foundation

// In-flight monitoring against the SimBrief OFP and the live aircraft: where the aircraft is on
// the route, fuel against the plan, the descent profile, stabilised approach gates, minimums
// callouts and the touchdown. Pure logic, fed by the panel once a second.

public enum Geo {
    /// Great-circle distance in nautical miles.
    public static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 3440.065
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// Where the aircraft is along the OFP's navlog.
public struct RouteProgress: Sendable, Equatable {
    /// Index of the last point passed (-1 before the first).
    public let lastPassed: Int
    /// Index of the next point.
    public let next: Int
    public let distanceToNext: Double
    /// Along the route to the last point (the destination), NM.
    public let distanceToGo: Double
    /// Fuel planned on board at this position, interpolated between the two points, OFP unit.
    public let plannedFuelNow: Double?

    /// Locates a position on the route: the nearest point, and whether it is behind (we are
    /// between it and the next) or ahead.
    public static func locate(latitude: Double, longitude: Double, on fixes: [SimBriefOFP.NavFix]) -> RouteProgress? {
        guard fixes.count >= 2 else { return nil }
        let distances = fixes.map { Geo.distance(latitude, longitude, $0.latitude, $0.longitude) }
        guard let nearest = distances.indices.min(by: { distances[$0] < distances[$1] }) else { return nil }
        func leg(_ i: Int) -> Double {
            Geo.distance(fixes[i].latitude, fixes[i].longitude, fixes[i + 1].latitude, fixes[i + 1].longitude)
        }
        var next = nearest
        if nearest + 1 < fixes.count, distances[nearest + 1] < leg(nearest) {
            next = nearest + 1
        }
        let distanceToNext = distances[next]
        let remaining = next + 1 < fixes.count ? (next..<(fixes.count - 1)).reduce(0.0) { $0 + leg($1) } : 0
        var planned = fixes[next].plannedFuel
        if next > 0, let before = fixes[next - 1].plannedFuel, let after = fixes[next].plannedFuel {
            let length = leg(next - 1)
            let fraction = length > 0 ? max(0, min(1, 1 - distanceToNext / length)) : 1
            planned = before + (after - before) * fraction
        }
        return RouteProgress(lastPassed: next - 1, next: next, distanceToNext: distanceToNext,
                             distanceToGo: distanceToNext + remaining, plannedFuelNow: planned)
    }
}

/// Fuel on board against the plan, with ICAO fuel states.
public struct FuelStatus: Sendable, Equatable {
    public enum Level: Int, Sendable, Comparable {
        /// Within 300 kg of the planned landing fuel or better.
        case onPlan
        /// Burning more than planned.
        case watch
        /// Below what the diversion needs: decide before committing to the destination.
        case noAlternate
        /// Predicted to land below the final reserve: MAYDAY FUEL.
        case mayday

        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// Actual minus planned now, kg (negative: less than planned).
    public let deviation: Double
    /// Planned landing fuel corrected by the deviation, kg.
    public let estimatedLanding: Double
    public let level: Level

    /// All in kilograms. `alternate` is the fuel to the alternate.
    public static func evaluate(actual: Double, plannedNow: Double, plannedLanding: Double,
                                finalReserve: Double, alternate: Double) -> FuelStatus {
        let deviation = actual - plannedNow
        let estimate = plannedLanding + deviation
        let level: Level
        if estimate < finalReserve {
            level = .mayday
        } else if estimate < finalReserve + alternate {
            level = .noAlternate
        } else if estimate < plannedLanding - 300 {
            level = .watch
        } else {
            level = .onPlan
        }
        return FuelStatus(deviation: deviation, estimatedLanding: estimate, level: level)
    }
}

/// Rule-of-three descent: 3 NM per 1000 ft plus 10 NM to slow down and configure.
public enum DescentProfile {
    public static let decelerationMiles = 10.0

    /// Distance from the destination at which the descent should start, NM.
    public static func requiredDistance(altitude: Double, destinationElevation: Double) -> Double {
        max(0, altitude - destinationElevation) / 1000 * 3 + decelerationMiles
    }

    /// Altitude on the 3:1 profile at a distance from the destination, ft.
    public static func idealAltitude(distanceToGo: Double, destinationElevation: Double) -> Double {
        destinationElevation + max(0, distanceToGo - decelerationMiles) * 1000 / 3
    }

    /// Feet above (positive) or below the profile.
    public static func deviation(altitude: Double, distanceToGo: Double, destinationElevation: Double) -> Double {
        altitude - idealAltitude(distanceToGo: distanceToGo, destinationElevation: destinationElevation)
    }
}

/// What the stabilised approach criteria look at.
public struct ApproachSnapshot: Sendable, Equatable {
    public var heightAboveField: Double
    public var landingConfiguration: Bool?
    public var gearDown: Bool?
    public var speed: Double?
    public var targetSpeed: Double?
    public var verticalSpeed: Double?
    public var localizerDots: Double?
    public var glideslopeDots: Double?

    public init(heightAboveField: Double, landingConfiguration: Bool? = nil, gearDown: Bool? = nil, speed: Double? = nil,
                targetSpeed: Double? = nil, verticalSpeed: Double? = nil, localizerDots: Double? = nil,
                glideslopeDots: Double? = nil) {
        self.heightAboveField = heightAboveField
        self.landingConfiguration = landingConfiguration
        self.gearDown = gearDown
        self.speed = speed
        self.targetSpeed = targetSpeed
        self.verticalSpeed = verticalSpeed
        self.localizerDots = localizerDots
        self.glideslopeDots = glideslopeDots
    }
}

public struct GateResult: Codable, Sendable, Equatable, Identifiable {
    /// 1000 or 500 ft above the field.
    public let gate: Int
    public let failures: [String]
    public let date: Date

    public var id: Int { gate }
    public var isStable: Bool { failures.isEmpty }

    /// Airline criteria: landing configuration, speed VAPP −5/+10, sink rate up to 1000 fpm,
    /// within one dot of the localizer and glideslope.
    public static func evaluate(_ s: ApproachSnapshot, gate: Int, at date: Date = Date()) -> GateResult {
        var failures: [String] = []
        if s.gearDown == false { failures.append("Tren no abajo") }
        if s.landingConfiguration == false { failures.append("Sin configuración de aterrizaje") }
        if let speed = s.speed, let target = s.targetSpeed, target > 0, speed < target - 5 || speed > target + 10 {
            failures.append("Velocidad \(Int(speed.rounded())) kt (VAPP \(Int(target.rounded())) −5/+10)")
        }
        if let vs = s.verticalSpeed, vs < -1000 {
            failures.append("Régimen \(Int((-vs).rounded())) ft/min (máximo 1000)")
        }
        if let loc = s.localizerDots, abs(loc) > 1 { failures.append("Fuera del localizador (\(String(format: "%.1f", abs(loc))) puntos)") }
        if let gs = s.glideslopeDots, abs(gs) > 1 { failures.append("Fuera de la senda (\(String(format: "%.1f", abs(gs))) puntos)") }
        return GateResult(gate: gate, failures: failures, date: date)
    }
}

/// Evaluates each gate once, when the aircraft descends through it.
public struct GateTracker: Sendable {
    public static let gates = [1000, 500]
    public private(set) var results: [GateResult] = []
    private var lastHeight: Double?

    public init() {}

    @discardableResult
    public mutating func update(_ snapshot: ApproachSnapshot, at date: Date = Date()) -> GateResult? {
        defer { lastHeight = snapshot.heightAboveField }
        guard let previous = lastHeight else { return nil }
        // Climbing well above the gates again (go-around, new approach) clears them.
        if snapshot.heightAboveField > 2000 { results.removeAll(); return nil }
        for gate in Self.gates where previous > Double(gate) && snapshot.heightAboveField <= Double(gate) {
            guard !results.contains(where: { $0.gate == gate }) else { continue }
            let result = GateResult.evaluate(snapshot, gate: gate, at: date)
            results.append(result)
            return result
        }
        return nil
    }
}

/// "100 above" and "Minimum" as the aircraft descends through the minimum + 100 ft and the
/// minimum (both as height above the field).
public struct MinimumsCallouts: Sendable {
    public enum Callout: String, Sendable {
        case hundredAbove = "ONE HUNDRED ABOVE"
        case minimum = "MINIMUM"
    }

    private var lastHeight: Double?
    private var called: Set<String> = []

    public init() {}

    public mutating func update(height: Double, minimum: Double) -> Callout? {
        defer { lastHeight = height }
        guard minimum > 0, let previous = lastHeight else { return nil }
        if height > minimum + 300 { called.removeAll() }
        if previous > minimum + 100, height <= minimum + 100, called.insert("100").inserted { return .hundredAbove }
        if previous > minimum, height <= minimum, called.insert("min").inserted { return .minimum }
        return nil
    }
}

/// The touchdown: sink rate at contact and the peak load factor just after.
public struct LandingReport: Codable, Sendable, Equatable {
    /// Feet per minute, positive down.
    public let rate: Int
    public let peakG: Double
    public let speed: Int?
    public let date: Date

    public var rating: String {
        if rate > 600 || peakG > 2.6 { return "Toma dura: requiere inspección (anótala en el parte técnico)" }
        switch rate {
        case ..<120: return "Muy suave (cuidado: en pista mojada se busca una toma firme)"
        case ..<240: return "Buena"
        case ..<360: return "Firme"
        default: return "Dura"
        }
    }

    public var isHard: Bool { rate > 600 || peakG > 2.6 }
}

/// Catches the touchdown from ground contact, vertical speed and load factor.
public struct LandingDetector: Sendable {
    private var airborneSince: Date?
    private var lastSink: Double = 0
    private var contact: (date: Date, rate: Double, speed: Double?)?
    private var peakG: Double = 1
    public private(set) var report: LandingReport?

    public init() {}

    /// Returns a report once, two seconds after a touchdown that followed at least 30 s airborne.
    public mutating func update(onGround: Bool, verticalSpeed: Double, g: Double, speed: Double?, at date: Date) -> LandingReport? {
        if !onGround {
            if airborneSince == nil { airborneSince = date }
            if contact == nil { lastSink = verticalSpeed }
            return nil
        }
        if contact == nil, let since = airborneSince, date.timeIntervalSince(since) > 30 {
            contact = (date, max(0, -lastSink), speed)
            peakG = g
        }
        airborneSince = nil
        guard let touch = contact else { return nil }
        peakG = max(peakG, g)
        if date.timeIntervalSince(touch.date) >= 2 {
            let finished = LandingReport(rate: Int(touch.rate.rounded()), peakG: (peakG * 100).rounded() / 100,
                                         speed: touch.speed.map { Int($0.rounded()) }, date: touch.date)
            report = finished
            contact = nil
            return finished
        }
        return nil
    }
}

/// A position report: what was planned and what happened at a navlog point.
public struct PositionReport: Codable, Sendable, Equatable, Identifiable {
    public let ident: String
    public let date: Date
    public let altitude: Int?
    /// Kilograms.
    public let actualFuel: Double?
    public let plannedFuel: Double?

    public var id: String { ident + "\(date.timeIntervalSince1970)" }
    public var deviation: Double? {
        guard let actualFuel, let plannedFuel else { return nil }
        return actualFuel - plannedFuel
    }
}

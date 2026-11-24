import Foundation

/// Time management en route: where the flight stands against the navlog's times, when it will
/// land and be on blocks, against the schedule, what speed change would bring it back on time,
/// and how long it could hold before eating into the alternate fuel.
public struct EnrouteTime: Sendable, Equatable {
    /// Seconds from take-off the navlog planned for the present position.
    public let plannedElapsed: TimeInterval
    /// Actual minus planned elapsed time here: positive is late. Nil without a take-off time.
    public let deviation: TimeInterval?
    /// Seconds from here to the destination, as the navlog plans the rest of the route.
    public let remaining: TimeInterval
    public let landing: Date
    public let inBlock: Date
    /// In-block estimate minus the schedule: positive is late. Nil without a schedule.
    public let arrivalDelay: TimeInterval?

    /// The navlog's time at a position on the route, interpolated along the leg flown.
    public static func plannedElapsed(at progress: RouteProgress, on fixes: [SimBriefOFP.NavFix]) -> TimeInterval? {
        guard fixes.indices.contains(progress.next), let nextTime = fixes[progress.next].timeTotal else { return nil }
        guard progress.next > 0, let previousTime = fixes[progress.next - 1].timeTotal else { return TimeInterval(nextTime) }
        let previous = fixes[progress.next - 1], next = fixes[progress.next]
        let leg = Geo.distance(previous.latitude, previous.longitude, next.latitude, next.longitude)
        let fraction = leg > 0 ? max(0, min(1, progress.distanceToNext / leg)) : 0
        return TimeInterval(nextTime) - TimeInterval(nextTime - previousTime) * fraction
    }

    /// - Parameters:
    ///   - takeOff: when the aircraft left the ground, if known.
    ///   - totalPlanned: the navlog's take-off to landing time, seconds.
    ///   - taxiIn: minutes from landing to on blocks.
    public static func evaluate(now: Date, takeOff: Date?, progress: RouteProgress, fixes: [SimBriefOFP.NavFix],
                                totalPlanned: TimeInterval, scheduledIn: Date?, taxiIn: Double) -> EnrouteTime? {
        guard let planned = plannedElapsed(at: progress, on: fixes) else { return nil }
        let remaining = max(0, totalPlanned - planned)
        let landing = now.addingTimeInterval(remaining)
        let inBlock = landing.addingTimeInterval(taxiIn * 60)
        return EnrouteTime(plannedElapsed: planned,
                           deviation: takeOff.map { now.timeIntervalSince($0) - planned },
                           remaining: remaining, landing: landing, inBlock: inBlock,
                           arrivalDelay: scheduledIn.map { inBlock.timeIntervalSince($0) })
    }
}

/// What speed change makes up (or gives back) time over the cruise left.
public struct SpeedAdvice: Sendable, Equatable {
    /// Knots of ground speed to add (negative: slow down).
    public let groundspeedChange: Double
    /// The same as a Mach change, when the Mach number is known.
    public let machChange: Double?
    /// Within what a cost index change gives (about ±25 kt).
    public let feasible: Bool

    /// - Parameters:
    ///   - late: seconds to make up (negative: early, time to give back).
    ///   - cruiseDistance: NM of cruise left, to the top of descent.
    ///   - tasPerMach: knots of true airspeed per 1.0 Mach (the local speed of sound).
    public static func toRecover(late: TimeInterval, cruiseDistance: Double, groundspeed: Double,
                                 tasPerMach: Double?) -> SpeedAdvice? {
        guard cruiseDistance > 20, groundspeed > 200, abs(late) >= 120 else { return nil }
        let hoursNow = cruiseDistance / groundspeed
        let hoursNeeded = hoursNow - late / 3600
        guard hoursNeeded > 0 else { return SpeedAdvice(groundspeedChange: .infinity, machChange: nil, feasible: false) }
        let change = cruiseDistance / hoursNeeded - groundspeed
        return SpeedAdvice(groundspeedChange: change,
                           machChange: tasPerMach.flatMap { $0 > 0 ? change / $0 : nil },
                           feasible: abs(change) <= 25)
    }
}

public enum HoldingTime {
    /// A320 holding fuel flow at low level, kg/h (about 2.2–2.5 t/h depending on weight).
    public static let fuelFlow: Double = 2_300

    /// Minutes of holding before the fuel at landing drops to final reserve plus alternate.
    public static func available(estimatedLandingFuel: Double, finalReserve: Double, alternate: Double) -> Int {
        let spare = estimatedLandingFuel - finalReserve - alternate
        return max(0, Int(spare / fuelFlow * 60))
    }
}

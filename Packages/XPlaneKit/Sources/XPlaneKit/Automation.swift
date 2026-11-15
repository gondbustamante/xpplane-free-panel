import Foundation

/// Fires once when the aircraft leaves the runway after a landing: the heading of the landing
/// roll is the runway's, and turning more than 50° off it at taxi speed means a turn onto a
/// taxiway. Stopping on the runway (holding, a backtrack not yet begun) does not fire it.
public struct RunwayExitDetector: Sendable {
    /// Degrees off the runway heading that count as turned off.
    public static let turnOff: Double = 50
    /// Ground speed (kt) below which the aircraft is taxiing, not rolling out.
    public static let taxiSpeed: Double = 40

    enum Phase: Equatable {
        case waiting, airborne, rollout, vacated
    }

    private(set) var phase: Phase = .waiting
    private var runwayHeading: Double?

    public init() {}

    /// `heading` in degrees (true or magnetic, as long as it is always the same one).
    public mutating func update(onGround: Bool, groundspeed: Double, heading: Double) -> Bool {
        if !onGround {
            phase = .airborne
            runwayHeading = nil
            return false
        }
        switch phase {
        case .waiting, .vacated:
            return false
        case .airborne:
            // Touchdown: the rollout follows the runway.
            phase = .rollout
            runwayHeading = heading
            return false
        case .rollout:
            if groundspeed > 60 {
                runwayHeading = heading
                return false
            }
            guard let runway = runwayHeading, groundspeed < Self.taxiSpeed,
                  Self.difference(heading, runway) > Self.turnOff else { return false }
            phase = .vacated
            return true
        }
    }

    static func difference(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b).truncatingRemainder(dividingBy: 360)
        return raw > 180 ? 360 - raw : raw
    }
}

/// When to run the flows tied to a moment of the flight: FL100 in the climb and the descent,
/// and parked at the stand after a flight (parking brake set and both engines shut down by the
/// pilot, for a few seconds so the engines have spooled down before the beacon goes off).
public struct AutomationTriggers: Sendable {
    public enum Event: Sendable, Equatable {
        case climbThroughFL100
        case descendThroughFL100
        case parked
    }

    public struct Snapshot: Sendable, Equatable {
        /// Indicated altitude, ft.
        public var altitude: Double
        public var onGround: Bool
        /// Knots.
        public var groundspeed: Double
        /// nil while unknown.
        public var parkingBrakeOn: Bool?
        public var enginesOff: Bool?

        public init(altitude: Double, onGround: Bool, groundspeed: Double,
                    parkingBrakeOn: Bool? = nil, enginesOff: Bool? = nil) {
            self.altitude = altitude
            self.onGround = onGround
            self.groundspeed = groundspeed
            self.parkingBrakeOn = parkingBrakeOn
            self.enginesOff = enginesOff
        }
    }

    public static let level: Double = 10_000
    /// Seconds parked with the engines off before the parking flow.
    public static let parkedHold: TimeInterval = 10

    private var previousAltitude: Double?
    /// FL100 is re-armed 500 ft away, so levelling off at FL100 does not fire it again.
    private var levelArmed = true
    /// Only after a flight: sitting cold and dark at the stand when the app connects is not
    /// an arrival.
    private var hasFlown = false
    private var parkedSince: Date?

    public init() {}

    public mutating func update(_ now: Snapshot, at date: Date) -> [Event] {
        defer { previousAltitude = now.altitude }
        var events: [Event] = []

        if abs(now.altitude - Self.level) > 500 { levelArmed = true }
        if !now.onGround {
            hasFlown = true
            parkedSince = nil
            if levelArmed, let before = previousAltitude {
                if before < Self.level, now.altitude >= Self.level {
                    events.append(.climbThroughFL100)
                    levelArmed = false
                } else if before > Self.level, now.altitude <= Self.level {
                    events.append(.descendThroughFL100)
                    levelArmed = false
                }
            }
            return events
        }

        guard hasFlown, now.groundspeed < 1, now.parkingBrakeOn == true, now.enginesOff == true else {
            parkedSince = nil
            return events
        }
        let since = parkedSince ?? date
        parkedSince = since
        if date.timeIntervalSince(since) >= Self.parkedHold {
            events.append(.parked)
            hasFlown = false
            parkedSince = nil
        }
        return events
    }
}

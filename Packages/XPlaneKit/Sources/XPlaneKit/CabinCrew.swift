import Foundation

/// The cabin side of a flight: when the crew and the captain speak to the passengers and when
/// the cabin reports secure, read from what the pilot does (beacon at push-back, strobe at
/// line-up, seat belt sign) and from the flight itself (cruise, descent, arrival).
/// Each moment happens once per flight, in order.
public struct CabinTimeline: Sendable {
    public enum Moment: String, Sendable, CaseIterable, Equatable {
        /// Beacon on before departure: doors closed, welcome on board.
        case welcome
        /// Some time into the taxi: the cabin reports secure for take-off.
        case cabinSecureTakeoff
        /// Strobe on at line-up: "cabin crew, seats for take-off".
        case seatsForTakeoff
        /// Seat belt sign off in the climb.
        case beltsOff
        /// Level in cruise for a couple of minutes: the captain's cruise announcement.
        case cruise
        /// Descending from cruise.
        case descent
        /// Below FL100 in the descent: the cabin reports secure for landing.
        case cabinSecureLanding
        /// Off the runway after landing: welcome to the destination.
        case arrival
        /// Beacon off at the stand: seat belts off, disembarking.
        case disembark
    }

    public struct Snapshot: Sendable, Equatable {
        public var onGround: Bool
        /// Knots.
        public var groundspeed: Double
        /// Feet.
        public var altitude: Double
        /// ft/min.
        public var verticalSpeed: Double
        public var beaconOn: Bool?
        public var strobeOn: Bool?
        public var seatBeltsOn: Bool?

        public init(onGround: Bool, groundspeed: Double, altitude: Double, verticalSpeed: Double,
                    beaconOn: Bool? = nil, strobeOn: Bool? = nil, seatBeltsOn: Bool? = nil) {
            self.onGround = onGround
            self.groundspeed = groundspeed
            self.altitude = altitude
            self.verticalSpeed = verticalSpeed
            self.beaconOn = beaconOn
            self.strobeOn = strobeOn
            self.seatBeltsOn = seatBeltsOn
        }
    }

    enum Phase: Equatable {
        case unknown, preflight, taxiOut, airborne, landed
    }

    /// Seconds of taxi before the cabin reports secure.
    public static let cabinSecureDelay: TimeInterval = 45
    /// Seconds level above FL200 before the cruise announcement.
    public static let cruiseDelay: TimeInterval = 120

    private(set) var phase: Phase = .unknown
    private var done: Set<Moment> = []
    private var previous: Snapshot?
    private var taxiStart: Date?
    private var levelSince: Date?
    /// Highest altitude of this flight: the descent is measured from it.
    private var topAltitude: Double = 0

    public init() {}

    public mutating func update(_ now: Snapshot, at date: Date) -> [Moment] {
        defer { previous = now }
        var moments: [Moment] = []
        func happen(_ moment: Moment) {
            if done.insert(moment).inserted { moments.append(moment) }
        }
        let before = previous
        func turnedOn(_ path: KeyPath<Snapshot, Bool?>) -> Bool {
            now[keyPath: path] == true && before?[keyPath: path] == false
        }
        func turnedOff(_ path: KeyPath<Snapshot, Bool?>) -> Bool {
            now[keyPath: path] == false && before?[keyPath: path] == true
        }

        switch phase {
        case .unknown:
            // Joined in flight: only what is still ahead.
            if now.onGround {
                phase = .preflight
            } else {
                phase = .airborne
                topAltitude = now.altitude
                done = [.welcome, .cabinSecureTakeoff, .seatsForTakeoff]
            }
        case .preflight:
            if turnedOn(\.beaconOn) { happen(.welcome) }
            if now.groundspeed > 5 {
                phase = .taxiOut
                taxiStart = date
            }
        case .taxiOut:
            if turnedOn(\.beaconOn) { happen(.welcome) }
            if let start = taxiStart, date.timeIntervalSince(start) >= Self.cabinSecureDelay { happen(.cabinSecureTakeoff) }
            if turnedOn(\.strobeOn) {
                // The report comes before the call to the seats, whatever the timing.
                happen(.cabinSecureTakeoff)
                happen(.seatsForTakeoff)
            }
            if !now.onGround {
                happen(.cabinSecureTakeoff)
                phase = .airborne
            }
        case .airborne:
            if turnedOff(\.seatBeltsOn), now.altitude > 5000 { happen(.beltsOff) }
            topAltitude = max(topAltitude, now.altitude)
            if now.altitude > 20_000, abs(now.verticalSpeed) < 300 {
                let since = levelSince ?? date
                levelSince = since
                if date.timeIntervalSince(since) >= Self.cruiseDelay { happen(.cruise) }
            } else {
                levelSince = nil
            }
            // Short flights may never reach FL200: the descent is 2000 ft below the top.
            if topAltitude > 8000, now.verticalSpeed < -500, now.altitude < topAltitude - 2000 { happen(.descent) }
            if done.contains(.descent), now.verticalSpeed < 0, now.altitude < min(10_000, topAltitude - 3000) {
                happen(.cabinSecureLanding)
            }
            if now.onGround {
                phase = .landed
            }
        case .landed:
            if !now.onGround {
                // Bounce or go-around.
                phase = .airborne
            } else {
                if now.groundspeed < 30 { happen(.arrival) }
                if turnedOff(\.beaconOn) {
                    happen(.arrival)
                    happen(.disembark)
                    // Next leg.
                    phase = .preflight
                    done = []
                    topAltitude = 0
                    levelSince = nil
                    taxiStart = nil
                }
            }
        }
        return moments
    }

    /// Temperature in a METAR, °C: "18/12" → 18, "M02/M05" → -2.
    public static func temperature(metar: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(?:^|\s)(M?\d{2})/(?:M?\d{2})?(?:\s|$)"#) else { return nil }
        let range = NSRange(metar.startIndex..., in: metar)
        guard let match = regex.firstMatch(in: metar, range: range),
              let group = Range(match.range(at: 1), in: metar) else { return nil }
        return Int(metar[group].replacingOccurrences(of: "M", with: "-"))
    }
}

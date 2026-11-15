import Foundation

/// The pilot monitoring's deviation calls on final approach (Airbus standard callouts): from
/// 1000 ft above the field down to the flare. A limit must be exceeded for a moment before the
/// call, so a gust does not trigger it, and it can be called again once back within limits.
/// Only after the aircraft has been above 1500 ft: the turns after take-off are not an approach.
public struct DeviationCallouts: Sendable {
    public enum Callout: String, Sendable, CaseIterable {
        case speed = "SPEED"
        case sinkRate = "SINK RATE"
        case bank = "BANK"
        case pitch = "PITCH"
        case localizer = "LOCALIZER"
        case glideslope = "GLIDESLOPE"
    }

    public struct Snapshot: Sendable, Equatable {
        public var heightAboveField: Double
        public var onGround: Bool
        public var ias: Double
        /// Managed or selected speed target (VAPP on final); nil or 0 when unknown.
        public var targetSpeed: Double?
        public var verticalSpeed: Double
        public var bank: Double
        public var pitch: Double
        public var localizerDots: Double?
        public var glideslopeDots: Double?

        public init(heightAboveField: Double, onGround: Bool, ias: Double, targetSpeed: Double? = nil,
                    verticalSpeed: Double, bank: Double = 0, pitch: Double = 0,
                    localizerDots: Double? = nil, glideslopeDots: Double? = nil) {
            self.heightAboveField = heightAboveField
            self.onGround = onGround
            self.ias = ias
            self.targetSpeed = targetSpeed
            self.verticalSpeed = verticalSpeed
            self.bank = bank
            self.pitch = pitch
            self.localizerDots = localizerDots
            self.glideslopeDots = glideslopeDots
        }
    }

    /// How long a limit must be exceeded before the call.
    public static let persistence: TimeInterval = 1.5

    private var armed = false
    private var exceededSince: [Callout: Date] = [:]
    private var called: Set<Callout> = []

    public init() {}

    public mutating func update(_ now: Snapshot, at date: Date) -> [Callout] {
        if now.onGround {
            armed = false
            reset()
            return []
        }
        if now.heightAboveField > 1500 {
            armed = true
            reset()
            return []
        }
        guard armed, now.heightAboveField <= 1000 else {
            reset()
            return []
        }
        var calls: [Callout] = []
        for callout in Callout.allCases {
            guard isExceeded(callout, now) else {
                exceededSince[callout] = nil
                called.remove(callout)
                continue
            }
            let since = exceededSince[callout] ?? date
            exceededSince[callout] = since
            if date.timeIntervalSince(since) >= Self.persistence, called.insert(callout).inserted {
                calls.append(callout)
            }
        }
        return calls
    }

    private mutating func reset() {
        exceededSince.removeAll()
        called.removeAll()
    }

    /// FCOM limits. Speed and sink rate stop at 50 ft (the flare bleeds speed and rate on
    /// purpose), the glideslope at 100 ft. Beyond 2.4 dots there is no usable ILS signal.
    private func isExceeded(_ callout: Callout, _ s: Snapshot) -> Bool {
        let height = s.heightAboveField
        switch callout {
        case .speed:
            guard height > 50, let target = s.targetSpeed, target > 0 else { return false }
            return s.ias < target - 5 || s.ias > target + 10
        case .sinkRate:
            return height > 50 && s.verticalSpeed < -1000
        case .bank:
            return abs(s.bank) > 7
        case .pitch:
            return s.pitch > 10 || s.pitch < -2.5
        case .localizer:
            guard let dots = s.localizerDots else { return false }
            return abs(dots) > 0.5 && abs(dots) < 2.4
        case .glideslope:
            guard height > 100, let dots = s.glideslopeDots else { return false }
            return abs(dots) > 1 && abs(dots) < 2.4
        }
    }
}

/// Altitude calls: 1000 ft before the FCU altitude, FL100 and the transition altitude (climb)
/// and level (descent), each once per crossing. A call is not repeated until the aircraft has
/// moved well away, so levelling off right at FL100 does not call it on every wobble.
public struct AltitudeCallouts: Sendable {
    public enum Callout: String, Sendable, CaseIterable {
        case oneThousandToGo = "ONE THOUSAND TO GO"
        case tenThousand = "TEN THOUSAND"
        case transitionAltitude = "TRANSITION ALTITUDE"
        case transitionLevel = "TRANSITION LEVEL"
    }

    public struct Snapshot: Sendable, Equatable {
        /// Indicated altitude, ft.
        public var altitude: Double
        public var verticalSpeed: Double
        public var onGround: Bool
        /// FCU altitude, ft.
        public var selectedAltitude: Double?
        /// Feet. Transition altitude of the departure, transition level of the arrival.
        public var transitionAltitude: Double?
        public var transitionLevel: Double?

        public init(altitude: Double, verticalSpeed: Double, onGround: Bool, selectedAltitude: Double? = nil,
                    transitionAltitude: Double? = nil, transitionLevel: Double? = nil) {
            self.altitude = altitude
            self.verticalSpeed = verticalSpeed
            self.onGround = onGround
            self.selectedAltitude = selectedAltitude
            self.transitionAltitude = transitionAltitude
            self.transitionLevel = transitionLevel
        }
    }

    private var previous: Snapshot?
    /// Calls made and the level they were made at; re-armed 500 ft away (1000-to-go: once the
    /// FCU altitude changes or the aircraft is 1200 ft away again).
    private var made: [Callout: Double] = [:]

    public init() {}

    public mutating func update(_ now: Snapshot) -> [Callout] {
        defer { previous = now }
        rearm(now)
        guard let before = previous, !now.onGround, !before.onGround else { return [] }
        var calls: [Callout] = []
        func call(_ callout: Callout, at level: Double) {
            guard made[callout] == nil else { return }
            made[callout] = level
            calls.append(callout)
        }

        // Approaching the FCU altitude, measured against the altitude selected now: setting a
        // new altitude less than 1000 ft away is not a crossing.
        if let selected = now.selectedAltitude, selected > 0 {
            let wasFar = abs(selected - before.altitude) > 1000
            let isNear = abs(selected - now.altitude) <= 1000
            let towards = (selected > now.altitude && now.verticalSpeed > 300)
                || (selected < now.altitude && now.verticalSpeed < -300)
            if wasFar, isNear, towards { call(.oneThousandToGo, at: selected) }
        }
        if crossed(10_000, from: before.altitude, to: now.altitude) != nil { call(.tenThousand, at: 10_000) }
        if let ta = now.transitionAltitude, ta > 0, crossed(ta, from: before.altitude, to: now.altitude) == .up {
            call(.transitionAltitude, at: ta)
        }
        if let tl = now.transitionLevel, tl > 0, crossed(tl, from: before.altitude, to: now.altitude) == .down {
            call(.transitionLevel, at: tl)
        }
        return calls
    }

    private mutating func rearm(_ now: Snapshot) {
        for (callout, level) in made {
            let rearmed: Bool
            if callout == .oneThousandToGo {
                rearmed = now.selectedAltitude != level || abs(level - now.altitude) > 1200
            } else {
                rearmed = abs(level - now.altitude) > 500
            }
            if rearmed { made[callout] = nil }
        }
    }

    private enum Direction { case up, down }

    private func crossed(_ level: Double, from old: Double, to new: Double) -> Direction? {
        if old < level, new >= level { return .up }
        if old > level, new <= level { return .down }
        return nil
    }
}

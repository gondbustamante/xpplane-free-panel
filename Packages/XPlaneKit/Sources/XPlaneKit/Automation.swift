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

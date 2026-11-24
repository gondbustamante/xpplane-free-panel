import Foundation

extension Geo {
    /// Initial great-circle bearing from the first point to the second, true degrees.
    public static func bearing(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }
}

/// The wind and temperature met against what the OFP planned at this point of the route: the
/// usual reason a flight goes slower or burns more than planned.
public struct WindComparison: Sendable, Equatable {
    public let plannedDirection: Double
    public let plannedSpeed: Double
    public let actualDirection: Double
    public let actualSpeed: Double
    /// Knots along the track, positive on the nose.
    public let plannedHeadwind: Double
    public let actualHeadwind: Double
    public let plannedISADeviation: Double?
    public let actualISADeviation: Double?

    /// Knots more on the nose than planned (negative: more tailwind than planned).
    public var headwindChange: Double { actualHeadwind - plannedHeadwind }

    /// Interpolates the navlog's wind and temperature between the two points of the leg flown and
    /// compares them with the wind and temperature measured now.
    public static func compare(progress: RouteProgress, fixes: [SimBriefOFP.NavFix], windDirection: Double,
                               windSpeed: Double, temperature: Double?, altitude: Double) -> WindComparison? {
        guard fixes.indices.contains(progress.next) else { return nil }
        let next = fixes[progress.next]
        let previous = progress.next > 0 ? fixes[progress.next - 1] : next
        guard let nextDirection = next.windDirection, let nextSpeed = next.windSpeed else { return nil }
        let leg = Geo.distance(previous.latitude, previous.longitude, next.latitude, next.longitude)
        let fraction = leg > 0 ? max(0, min(1, 1 - progress.distanceToNext / leg)) : 1
        // Winds are interpolated as vectors, so 350° and 010° average to 000°, not 180°.
        func vector(_ direction: Int?, _ speed: Int?) -> (Double, Double)? {
            guard let direction, let speed else { return nil }
            let radians = Double(direction) * .pi / 180
            return (Double(speed) * sin(radians), Double(speed) * cos(radians))
        }
        let b = vector(nextDirection, nextSpeed)!
        let a = vector(previous.windDirection, previous.windSpeed) ?? b
        let x = a.0 + (b.0 - a.0) * fraction, y = a.1 + (b.1 - a.1) * fraction
        let plannedSpeed = (x * x + y * y).squareRoot()
        let plannedDirection = (atan2(x, y) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)

        let track = progress.next > 0
            ? Geo.bearing(previous.latitude, previous.longitude, next.latitude, next.longitude)
            : plannedDirection
        func headwind(_ direction: Double, _ speed: Double) -> Double {
            speed * cos((direction - track) * .pi / 180)
        }
        let plannedISA: Double? = {
            let values = [previous.isaDeviation, next.isaDeviation].compactMap { $0 }.map(Double.init)
            return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        }()
        return WindComparison(plannedDirection: plannedDirection, plannedSpeed: plannedSpeed,
                              actualDirection: windDirection, actualSpeed: windSpeed,
                              plannedHeadwind: headwind(plannedDirection, plannedSpeed),
                              actualHeadwind: headwind(windDirection, windSpeed),
                              plannedISADeviation: plannedISA,
                              actualISADeviation: temperature.map { $0 - isaTemperature(altitude: altitude) })
    }

    /// ISA temperature at a pressure altitude, °C (constant above the tropopause).
    public static func isaTemperature(altitude: Double) -> Double {
        max(-56.5, 15 - 1.98 * altitude / 1000)
    }
}

import Foundation

/// The flight seen from the side, like the A350's vertical display: the planned profile from
/// the OFP navlog against distance along the route, where the aircraft is on it, and where its
/// present path takes it. Distances are measured along the route from the first navlog point,
/// the same way `RouteProgress` measures the distance to go, so both agree.
public struct VerticalProfile: Sendable, Equatable {
    public struct Point: Sendable, Equatable {
        /// NM along the route (negative before the first navlog point).
        public var distance: Double
        /// Feet.
        public var altitude: Double
        /// Point name for the ones worth labelling (TOC, TOD, airports).
        public var label: String?

        public init(distance: Double, altitude: Double, label: String? = nil) {
            self.distance = distance
            self.altitude = altitude
            self.label = label
        }
    }

    /// An airport at either end of the route.
    public struct Endpoint: Sendable, Equatable {
        public var ident: String
        public var latitude: Double
        public var longitude: Double
        public var elevation: Double

        public init(ident: String, latitude: Double, longitude: Double, elevation: Double) {
            self.ident = ident
            self.latitude = latitude
            self.longitude = longitude
            self.elevation = elevation
        }
    }

    /// Origin, every navlog point with a planned altitude, destination.
    public let planned: [Point]
    /// TOC, TOD and the two airports, to label on the profile.
    public let landmarks: [Point]
    /// Route length from the first navlog point to the last.
    public let routeLength: Double
    /// Distance of the destination along the route.
    public let destinationDistance: Double
    public let destinationElevation: Double
    private let fixes: [SimBriefOFP.NavFix]

    public init(fixes: [SimBriefOFP.NavFix], origin: Endpoint?, destination: Endpoint?) {
        self.fixes = fixes
        var cumulative: [Double] = []
        var total = 0.0
        for (index, fix) in fixes.enumerated() {
            if index > 0 {
                let previous = fixes[index - 1]
                total += Geo.distance(previous.latitude, previous.longitude, fix.latitude, fix.longitude)
            }
            cumulative.append(total)
        }
        routeLength = total

        var planned: [Point] = []
        var landmarks: [Point] = []
        if let origin, let first = fixes.first {
            let point = Point(distance: -Geo.distance(origin.latitude, origin.longitude, first.latitude, first.longitude),
                              altitude: origin.elevation, label: origin.ident)
            planned.append(point)
            landmarks.append(point)
        }
        for (index, fix) in fixes.enumerated() {
            guard let altitude = fix.altitude else { continue }
            let isProfilePoint = fix.type == "ltlg" && ["TOC", "TOD"].contains(fix.ident)
            let point = Point(distance: cumulative[index], altitude: Double(altitude), label: isProfilePoint ? fix.ident : nil)
            planned.append(point)
            if isProfilePoint { landmarks.append(point) }
        }
        var end = total
        if let destination, let last = fixes.last {
            end = total + Geo.distance(last.latitude, last.longitude, destination.latitude, destination.longitude)
            let point = Point(distance: end, altitude: destination.elevation, label: destination.ident)
            planned.append(point)
            landmarks.append(point)
        }
        self.planned = planned
        self.landmarks = landmarks
        destinationDistance = end
        destinationElevation = destination?.elevation ?? 0
    }

    /// Distance along the route of a position.
    public func distanceAlong(latitude: Double, longitude: Double) -> Double? {
        RouteProgress.locate(latitude: latitude, longitude: longitude, on: fixes).map { routeLength - $0.distanceToGo }
    }

    /// The planned altitude at a distance along the route, between the two planned points.
    public func plannedAltitude(at distance: Double) -> Double? {
        guard let after = planned.firstIndex(where: { $0.distance >= distance }) else { return planned.last?.altitude }
        guard after > 0 else { return planned.first?.altitude }
        let a = planned[after - 1], b = planned[after]
        guard b.distance > a.distance else { return b.altitude }
        return a.altitude + (b.altitude - a.altitude) * (distance - a.distance) / (b.distance - a.distance)
    }

    /// The 3:1 descent path into the destination (with 10 NM to slow down), from the
    /// destination back to where it reaches `ceiling`.
    public func descentPath(ceiling: Double) -> [Point] {
        let top = max(ceiling, destinationElevation)
        let length = DescentProfile.requiredDistance(altitude: top, destinationElevation: destinationElevation)
        return [
            Point(distance: destinationDistance, altitude: destinationElevation),
            Point(distance: destinationDistance - DescentProfile.decelerationMiles, altitude: destinationElevation),
            Point(distance: destinationDistance - length, altitude: top),
        ]
    }

    /// Where the present path goes over the next `ahead` NM: the current vertical speed over the
    /// ground speed, levelling off at the FCU altitude when climbing or descending towards it.
    /// Empty below 50 kt (on the ground).
    public static func projection(distance: Double, altitude: Double, groundspeed: Double, verticalSpeed: Double,
                                  selectedAltitude: Double?, ahead: Double) -> [Point] {
        guard groundspeed > 50, ahead > 0 else { return [] }
        let start = Point(distance: distance, altitude: altitude)
        // Feet per NM.
        let gradient = verticalSpeed / (groundspeed / 60)
        guard abs(verticalSpeed) >= 100 else {
            return [start, Point(distance: distance + ahead, altitude: altitude)]
        }
        if let target = selectedAltitude, target > 0, (target - altitude) * verticalSpeed > 0 {
            let levelOff = (target - altitude) / gradient
            if levelOff < ahead {
                return [start, Point(distance: distance + levelOff, altitude: target),
                        Point(distance: distance + ahead, altitude: target)]
            }
        }
        return [start, Point(distance: distance + ahead, altitude: max(0, altitude + gradient * ahead))]
    }
}

public extension VerticalProfile {
    init(ofp: SimBriefOFP) {
        func endpoint(_ airport: SimBriefOFP.Airport) -> Endpoint? {
            guard let latitude = airport.latitude, let longitude = airport.longitude else { return nil }
            return Endpoint(ident: airport.icao, latitude: latitude, longitude: longitude,
                            elevation: Double(airport.elevation ?? 0))
        }
        self.init(fixes: ofp.fixes, origin: endpoint(ofp.origin), destination: endpoint(ofp.destination))
    }
}

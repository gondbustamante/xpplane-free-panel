import Foundation

/// A SIGMET: an area of significant weather (turbulence, icing, thunderstorms, volcanic ash...)
/// with its levels and validity, as aviationweather.gov publishes the international ones.
public struct Sigmet: Sendable, Equatable, Identifiable, Codable {
    public enum Hazard: String, Sendable, Codable {
        case turbulence, icing, thunderstorm, volcanicAsh, mountainWave, other

        public var title: String {
            switch self {
            case .turbulence: return "Turbulencia"
            case .icing: return "Engelamiento"
            case .thunderstorm: return "Tormentas"
            case .volcanicAsh: return "Ceniza volcánica"
            case .mountainWave: return "Onda de montaña"
            case .other: return "Fenómeno significativo"
            }
        }
    }

    public struct Point: Sendable, Equatable, Codable {
        public var latitude: Double
        public var longitude: Double
    }

    public var id: String
    public var hazard: Hazard
    /// "SEV", "EMBD", "OBSC"…
    public var qualifier: String?
    public var fir: String?
    /// Feet; nil when the SIGMET does not say (surface or unknown).
    public var base: Int?
    public var top: Int?
    public var validFrom: Date?
    public var validTo: Date?
    public var area: [Point]
    public var raw: String?

    public var title: String {
        [qualifier.flatMap(Self.qualifierTitle), hazard.title.lowercased()].compactMap { $0 }.joined(separator: " ")
            .capitalizedFirst
    }

    static func qualifierTitle(_ code: String) -> String? {
        switch code.uppercased() {
        case "SEV": return "Fuerte"
        case "MOD": return "Moderada"
        case "EMBD": return "Embebidas"
        case "OBSC": return "Ocultas"
        case "FRQ": return "Frecuentes"
        case "SQL": return "En línea"
        default: return nil
        }
    }

    /// Reads the JSON of aviationweather.gov's isigmet (or airsigmet) feed. Key names vary between
    /// the two and over time, so each value is looked for under its usual names; entries without
    /// an area are skipped.
    public static func decode(json data: Data) -> [Sigmet] {
        guard let items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        return items.enumerated().compactMap { index, item in
            func value(_ keys: String...) -> Any? { keys.lazy.compactMap { item[$0] }.first { !($0 is NSNull) } }
            func text(_ keys: String...) -> String? {
                keys.lazy.compactMap { item[$0] as? String }.first { !$0.isEmpty }
            }
            func number(_ keys: String...) -> Double? {
                for key in keys {
                    if let number = item[key] as? NSNumber { return number.doubleValue }
                    if let string = item[key] as? String, let number = Double(string) { return number }
                }
                return nil
            }
            func date(_ keys: String...) -> Date? {
                for key in keys {
                    if let number = item[key] as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue) }
                    if let string = item[key] as? String, let parsed = ISO8601DateFormatter().date(from: string) { return parsed }
                }
                return nil
            }
            let area: [Point] = ((value("coords", "coordinates") as? [[String: Any]]) ?? []).compactMap { point in
                func coordinate(_ key: String) -> Double? {
                    (point[key] as? NSNumber)?.doubleValue ?? (point[key] as? String).flatMap(Double.init)
                }
                guard let lat = coordinate("lat"), let lon = coordinate("lon") else { return nil }
                return Point(latitude: lat, longitude: lon)
            }
            guard area.count >= 3 else { return nil }
            let hazardCode = (text("hazard") ?? "").uppercased()
            let hazard: Hazard
            switch hazardCode {
            case let code where code.contains("TURB"): hazard = .turbulence
            case let code where code.contains("ICE") || code.contains("ICING"): hazard = .icing
            case let code where code.contains("TS") || code.contains("CONVECTIVE"): hazard = .thunderstorm
            case let code where code.contains("VA") || code.contains("ASH"): hazard = .volcanicAsh
            case let code where code.contains("MTW"): hazard = .mountainWave
            default: hazard = .other
            }
            func feet(_ keys: String...) -> Int? {
                for key in keys { if let n = number(key) { return Int(n) } }
                return nil
            }
            let id = [text("firId", "icaoId"), text("seriesId"), (date("validTimeFrom")?.timeIntervalSince1970).map { String(Int($0)) }]
                .compactMap { $0 }.joined(separator: "-")
            return Sigmet(id: id.isEmpty ? "sigmet-\(index)" : id + "-\(index)", hazard: hazard,
                          qualifier: text("qualifier", "severity"),
                          fir: text("firName", "firId"),
                          base: feet("base", "altitudeLow1", "altitudeLow"),
                          top: feet("top", "altitudeHi1", "altitudeHi2", "altitudeHi"),
                          validFrom: date("validTimeFrom"), validTo: date("validTimeTo"),
                          area: area, raw: text("rawSigmet", "rawAirSigmet"))
        }
    }

    /// Point in the area (ray casting on latitude and longitude: fine for areas of a few hundred
    /// miles away from the poles and the antimeridian).
    public func contains(latitude: Double, longitude: Double) -> Bool {
        var inside = false
        var j = area.count - 1
        for i in area.indices {
            let a = area[i], b = area[j]
            if (a.latitude > latitude) != (b.latitude > latitude) {
                let crossing = (b.longitude - a.longitude) * (latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
                if longitude < crossing { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// The levels overlap a band of altitudes (both in feet). Unknown limits count as overlapping.
    public func overlaps(lower: Double, upper: Double) -> Bool {
        let base = Double(self.base ?? 0), top = Double(self.top ?? 60_000)
        return base <= upper && top >= lower
    }
}

/// Where a SIGMET sits on the route: along-route distances where the route enters and leaves it,
/// and whether the planned levels there are inside its vertical limits.
public struct RouteHazard: Sendable, Equatable, Identifiable {
    public let sigmet: Sigmet
    /// NM along the route (as `VerticalProfile` measures it).
    public let entry: Double
    public let exit: Double
    /// The planned profile crosses it at its levels.
    public let atPlannedLevels: Bool

    public var id: String { sigmet.id }

    /// SIGMETs the route goes through, in route order. The route is sampled every `step` NM.
    public static func along(_ profile: VerticalProfile, fixes: [SimBriefOFP.NavFix], sigmets: [Sigmet],
                             now: Date, step: Double = 5) -> [RouteHazard] {
        guard fixes.count >= 2 else { return [] }
        // Sample points along the route with their distance.
        var samples: [(distance: Double, latitude: Double, longitude: Double)] = []
        var travelled = 0.0
        for index in 1..<fixes.count {
            let a = fixes[index - 1], b = fixes[index]
            let leg = Geo.distance(a.latitude, a.longitude, b.latitude, b.longitude)
            let count = max(1, Int(leg / step))
            for k in 0..<count {
                let f = Double(k) / Double(count)
                samples.append((travelled + leg * f, a.latitude + (b.latitude - a.latitude) * f,
                                a.longitude + (b.longitude - a.longitude) * f))
            }
            travelled += leg
        }
        samples.append((travelled, fixes[fixes.count - 1].latitude, fixes[fixes.count - 1].longitude))

        return sigmets.compactMap { sigmet -> RouteHazard? in
            if let end = sigmet.validTo, end < now { return nil }
            let inside = samples.filter { sigmet.contains(latitude: $0.latitude, longitude: $0.longitude) }
            guard let first = inside.first, let last = inside.last else { return nil }
            let altitudes = inside.compactMap { profile.plannedAltitude(at: $0.distance) }
            let atLevels = altitudes.isEmpty || sigmet.overlaps(lower: altitudes.min()!, upper: altitudes.max()!)
            return RouteHazard(sigmet: sigmet, entry: first.distance, exit: last.distance, atPlannedLevels: atLevels)
        }
        .sorted { $0.entry < $1.entry }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

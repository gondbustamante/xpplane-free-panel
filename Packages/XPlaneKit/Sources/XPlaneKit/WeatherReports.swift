import Foundation

// METAR and TAF decoded from their raw text: what matters for an arrival decision (wind, visibility,
// ceiling, weather, flight category) and the TAF's change groups with their validity.

public enum FlightCategory: Int, Sendable, Comparable, Codable {
    case vfr, mvfr, ifr, lifr

    public static func < (lhs: FlightCategory, rhs: FlightCategory) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .vfr: return "VFR"
        case .mvfr: return "MVFR"
        case .ifr: return "IFR"
        case .lifr: return "LIFR"
        }
    }

    /// FAA thresholds: ceiling (ft) and visibility (m; 1, 3 and 5 statute miles).
    public static func from(ceiling: Int?, visibility: Int?) -> FlightCategory {
        let ceiling = ceiling ?? .max, visibility = visibility ?? .max
        if ceiling < 500 || visibility < 1_609 { return .lifr }
        if ceiling < 1_000 || visibility < 4_828 { return .ifr }
        if ceiling <= 3_000 || visibility <= 8_047 { return .mvfr }
        return .vfr
    }
}

/// The conditions one report (or one TAF group) gives.
public struct WeatherConditions: Sendable, Equatable, Codable {
    /// True degrees; nil when variable.
    public var windDirection: Int?
    public var windSpeed: Int?
    public var gust: Int?
    /// Metres; 10000 means 10 km or more.
    public var visibility: Int?
    /// Lowest broken or overcast layer (or vertical visibility), feet.
    public var ceiling: Int?
    /// Weather groups as written: "+TSRA", "FG", "-SN".
    public var weather: [String] = []
    public var temperature: Int?
    public var dewpoint: Int?
    public var qnh: Int?
    public var cavok = false

    public init() {}

    public var category: FlightCategory { .from(ceiling: ceiling, visibility: visibility) }
    public var hasThunderstorm: Bool { weather.contains { $0.contains("TS") } }
    /// Freezing precipitation or fog, snow: the arrival needs a closer look.
    public var hasSignificantWeather: Bool {
        weather.contains { group in ["TS", "FZ", "FG", "SN", "GR", "SQ", "FC", "+"].contains { group.contains($0) } }
    }

    /// Reads the groups a METAR or a TAF group shares. Tokens it does not know are ignored.
    mutating func read(_ tokens: [String]) {
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            defer { index += 1 }
            if let wind = Self.wind(token) {
                windDirection = wind.direction
                windSpeed = wind.speed
                gust = wind.gust
            } else if token == "CAVOK" {
                cavok = true
                visibility = 10_000
            } else if token.count == 4, let metres = Int(token), !token.contains("/") {
                visibility = metres == 9999 ? 10_000 : metres
            } else if token.hasSuffix("SM"), let miles = Self.statuteMiles(String(token.dropLast(2))) {
                // "1 1/2SM": the whole miles are the token before.
                var total = miles
                if token.contains("/"), index > 0, let whole = Double(tokens[index - 1]), visibility == Int(whole * 1609) {
                    total += whole
                }
                visibility = min(10_000, Int(total * 1609))
            } else if let layer = Self.cloud(token) {
                if layer.isCeiling { ceiling = min(ceiling ?? .max, layer.base) }
            } else if Self.isWeather(token) {
                weather.append(token)
            } else if let temperatures = Self.temperatures(token) {
                temperature = temperatures.0
                dewpoint = temperatures.1
            } else if token.hasPrefix("Q"), token.count == 5, let hectopascals = Int(token.dropFirst()) {
                qnh = hectopascals
            } else if token.hasPrefix("A"), token.count == 5, let hundredths = Double(token.dropFirst()) {
                qnh = Int((hundredths / 100 * 33.8639).rounded())
            } else if token.allSatisfy(\.isNumber), token.count == 1 || token.count == 2,
                      index + 1 < tokens.count, tokens[index + 1].hasSuffix("SM") {
                // Whole statute miles before a fraction: "1 1/2SM".
                if let whole = Double(token) { visibility = Int(whole * 1609) }
            }
        }
    }

    static func wind(_ token: String) -> (direction: Int?, speed: Int, gust: Int?)? {
        let units: [(String, Double)] = [("KT", 1), ("MPS", 1.94384), ("KMH", 0.539957)]
        guard let unit = units.first(where: { token.hasSuffix($0.0) }) else { return nil }
        let body = String(token.dropLast(unit.0.count))
        guard body.count >= 5 else { return nil }
        let direction = String(body.prefix(3))
        guard direction == "VRB" || Int(direction) != nil else { return nil }
        let rest = body.dropFirst(3).split(separator: "G", maxSplits: 1)
        guard let speed = rest.first.flatMap({ Double($0) }) else { return nil }
        let gust = rest.count > 1 ? Double(rest[1]) : nil
        return (Int(direction), Int((speed * unit.1).rounded()), gust.map { Int(($0 * unit.1).rounded()) })
    }

    static func statuteMiles(_ text: String) -> Double? {
        let clean = text.hasPrefix("P") || text.hasPrefix("M") ? String(text.dropFirst()) : text
        if let value = Double(clean) { return value }
        let parts = clean.split(separator: "/")
        guard parts.count == 2, let top = Double(parts[0]), let bottom = Double(parts[1]), bottom > 0 else { return nil }
        return top / bottom
    }

    static func cloud(_ token: String) -> (base: Int, isCeiling: Bool)? {
        for cover in ["FEW", "SCT", "BKN", "OVC", "VV"] where token.hasPrefix(cover) {
            let digits = token.dropFirst(cover.count).prefix(3)
            guard digits.count == 3, let hundreds = Int(digits) else { return nil }
            return (hundreds * 100, ["BKN", "OVC", "VV"].contains(cover))
        }
        return nil
    }

    static func isWeather(_ token: String) -> Bool {
        let pattern = #"^(\+|-|VC)?(MI|BC|PR|DR|BL|SH|TS|FZ)?(DZ|RA|SN|SG|IC|PL|GR|GS|UP|BR|FG|FU|VA|DU|SA|HZ|PY|PO|SQ|FC|SS|DS)*$"#
        guard token.count >= 2, token != "NSW", token.range(of: pattern, options: .regularExpression) != nil else { return false }
        // A bare intensity or descriptor is not weather, except a thunderstorm.
        return token.contains("TS") || token.range(of: "(DZ|RA|SN|SG|IC|PL|GR|GS|UP|BR|FG|FU|VA|DU|SA|HZ|PY|PO|SQ|FC|SS|DS)", options: .regularExpression) != nil
    }

    static func temperatures(_ token: String) -> (Int, Int?)? {
        let parts = token.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        func celsius(_ text: Substring) -> Int? {
            guard text.count == 2 || text.count == 3 else { return nil }
            let negative = text.hasPrefix("M")
            guard let value = Int(negative ? text.dropFirst() : text) else { return nil }
            return negative ? -value : value
        }
        guard let temperature = celsius(parts[0]) else { return nil }
        return (temperature, parts[1].isEmpty ? nil : celsius(parts[1]))
    }
}

public struct METARReport: Sendable, Equatable, Codable {
    public var station: String
    public var raw: String
    public var conditions: WeatherConditions

    /// "METAR LEMD 241030Z 02008KT CAVOK 12/M02 Q1021 NOSIG".
    public static func decode(_ raw: String) -> METARReport? {
        var tokens = raw.uppercased().split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = tokens.first, ["METAR", "SPECI", "COR", "AUTO"].contains(first) { tokens.removeFirst() }
        guard let station = tokens.first, station.count == 4, station.allSatisfy(\.isLetter) else { return nil }
        // Trends and remarks describe what may come, not what is.
        let body = tokens.dropFirst().prefix { !["NOSIG", "BECMG", "TEMPO", "RMK"].contains($0) }
        var conditions = WeatherConditions()
        conditions.read(Array(body))
        return METARReport(station: station, raw: raw, conditions: conditions)
    }
}

public struct TAFReport: Sendable, Equatable, Codable {
    public struct Group: Sendable, Equatable, Codable {
        public enum Change: String, Sendable, Codable { case base, from, becoming, temporary, probability }
        public var change: Change
        public var probability: Int?
        public var start: Date
        public var end: Date
        public var conditions: WeatherConditions
    }

    public var station: String
    public var raw: String
    public var groups: [Group]

    /// Decodes a TAF, dating its groups in the month of `reference` (the day they are read).
    public static func decode(_ raw: String, reference: Date) -> TAFReport? {
        var tokens = raw.uppercased().split(whereSeparator: \.isWhitespace).map(String.init)
        while let first = tokens.first, ["TAF", "AMD", "COR"].contains(first) { tokens.removeFirst() }
        guard let station = tokens.first, station.count == 4 else { return nil }
        tokens.removeFirst()
        // Issue time "241100Z", then the validity "2412/2518".
        if let first = tokens.first, first.hasSuffix("Z") { tokens.removeFirst() }
        guard let validity = tokens.first, let (validFrom, validTo) = period(validity, reference: reference) else { return nil }
        tokens.removeFirst()

        var groups: [Group] = []
        var current = Group(change: .base, probability: nil, start: validFrom, end: validTo, conditions: WeatherConditions())
        var pending: [String] = []
        func close() {
            current.conditions.read(pending)
            groups.append(current)
            pending = []
        }
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            if token == "RMK" { break }
            if token.hasPrefix("FM"), token.count >= 8, let start = time(String(token.dropFirst(2).prefix(6)), reference: reference) {
                close()
                current = Group(change: .from, probability: nil, start: start, end: validTo, conditions: WeatherConditions())
            } else if ["TEMPO", "BECMG"].contains(token) || token.hasPrefix("PROB") {
                close()
                let change: Group.Change = token == "TEMPO" ? .temporary : token == "BECMG" ? .becoming : .probability
                let probability = token.hasPrefix("PROB") ? Int(token.dropFirst(4)) : nil
                // "PROB30 TEMPO 2512/2515".
                if change == .probability, index + 1 < tokens.count, tokens[index + 1] == "TEMPO" { index += 1 }
                var start = validFrom, end = validTo
                if index + 1 < tokens.count, let span = period(tokens[index + 1], reference: reference) {
                    (start, end) = span
                    index += 1
                }
                current = Group(change: change, probability: probability, start: start, end: end, conditions: WeatherConditions())
            } else {
                pending.append(token)
            }
            index += 1
        }
        close()
        // "FM" groups end where the next one starts.
        for i in groups.indices where groups[i].change == .from || groups[i].change == .base {
            if let next = groups[(i + 1)...].first(where: { $0.change == .from }) { groups[i].end = next.start }
        }
        return TAFReport(station: station, raw: raw, groups: groups)
    }

    /// The worst of what the TAF gives in a time window: the prevailing groups and any TEMPO or
    /// PROB group that overlaps it.
    public func worst(from start: Date, to end: Date) -> WeatherConditions? {
        let overlapping = groups.filter { $0.start < end && $0.end > start }
        guard !overlapping.isEmpty else { return nil }
        var worst = overlapping[0].conditions
        for group in overlapping.dropFirst() {
            let c = group.conditions
            // A change group only says what changes: keep the base values it does not give.
            if let visibility = c.visibility { worst.visibility = min(worst.visibility ?? .max, visibility) }
            if let ceiling = c.ceiling { worst.ceiling = min(worst.ceiling ?? .max, ceiling) }
            if let speed = c.windSpeed, speed >= (worst.windSpeed ?? 0) {
                worst.windSpeed = speed
                worst.windDirection = c.windDirection ?? worst.windDirection
            }
            if let gust = c.gust { worst.gust = max(worst.gust ?? 0, gust) }
            worst.weather += c.weather.filter { !worst.weather.contains($0) }
        }
        return worst
    }

    /// "2412/2518": day and hour to day and hour, in the reference month ("24" for 24:00).
    static func period(_ token: String, reference: Date) -> (Date, Date)? {
        let parts = token.split(separator: "/")
        guard parts.count == 2, parts[0].count == 4, parts[1].count == 4,
              let start = time(String(parts[0]) + "00", reference: reference),
              var end = time(String(parts[1]) + "00", reference: reference) else { return nil }
        if end <= start { end = Calendar.utc.date(byAdding: .month, value: 1, to: end) ?? end }
        return (start, end)
    }

    /// "241200" (day, hour, minute) as a date near `reference`: the TAF's month, or the next one
    /// when the day has already wrapped.
    static func time(_ text: String, reference: Date) -> Date? {
        guard text.count == 6, let day = Int(text.prefix(2)), let hour = Int(text.dropFirst(2).prefix(2)),
              let minute = Int(text.suffix(2)), (1...31).contains(day) else { return nil }
        let calendar = Calendar.utc
        var components = calendar.dateComponents([.year, .month], from: reference)
        components.day = day
        components.hour = 0
        components.minute = minute
        guard var date = calendar.date(from: components) else { return nil }
        date.addTimeInterval(TimeInterval(hour) * 3600)
        // More than ten days away from the reference: it belongs to the month before or after.
        let gap = date.timeIntervalSince(reference)
        if gap > 10 * 86_400 { date = calendar.date(byAdding: .month, value: -1, to: date) ?? date }
        if gap < -10 * 86_400 { date = calendar.date(byAdding: .month, value: 1, to: date) ?? date }
        return date
    }
}

/// Wind components on a runway.
public struct RunwayWind: Sendable, Equatable {
    /// Knots, positive from the right.
    public let crosswind: Double
    /// Knots, positive on the nose; negative is a tailwind.
    public let headwind: Double

    /// A320 limits: 38 kt crosswind demonstrated (gusts included), 10 kt tailwind.
    public static let crosswindLimit = 38.0
    public static let tailwindLimit = 10.0

    /// Runway "25R" → 250°, against a wind from `direction` (true; the few degrees of variation
    /// are within the precision of a METAR). Uses the gust when there is one.
    public static func components(runway: String, direction: Int?, speed: Int?, gust: Int?) -> RunwayWind? {
        guard let direction, let speed, let number = Int(runway.prefix { $0.isNumber }), (1...36).contains(number) else { return nil }
        let strength = Double(max(speed, gust ?? 0))
        let angle = Double(direction - number * 10) * .pi / 180
        return RunwayWind(crosswind: strength * sin(angle), headwind: strength * cos(angle))
    }

    public var exceedsLimits: Bool { abs(crosswind) > Self.crosswindLimit || -headwind > Self.tailwindLimit }
}

extension Calendar {
    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

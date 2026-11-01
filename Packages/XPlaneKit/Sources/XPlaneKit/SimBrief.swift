import Foundation

// SimBrief operational flight plan (OFP), as the SimBrief API returns it:
//   https://www.simbrief.com/api/xml.fetcher.php?username=<user>&json=1   (or userid=<pilot id>)
// SimBrief sends every value as text and an empty object `{}` for a missing one, so the parser
// reads loosely and keeps only what the MCDU guide and the turnaround use.

public struct SimBriefOFP: Codable, Sendable, Equatable {
    public struct Airport: Codable, Sendable, Equatable {
        public var icao: String
        public var name: String?
        public var elevation: Int?
        public var runway: String?
        /// Transition altitude and level, feet.
        public var transitionAltitude: Int?
        public var transitionLevel: Int?
        public var metar: String?
        public var latitude: Double? = nil
        public var longitude: Double? = nil
        /// "vfr", "mvfr", "ifr", "lifr" from the METAR.
        public var weatherCategory: String? = nil
        public var taf: String? = nil
        /// ATIS messages SimBrief found (VATSIM and others).
        public var atis: [String]? = nil
        public var notams: [String]? = nil
    }

    /// A navlog point: where it is, how far from the previous one and the fuel planned on board.
    public struct NavFix: Codable, Sendable, Equatable {
        public var ident: String
        /// "wpt", "vor", "apt", or "ltlg" for TOC/TOD.
        public var type: String?
        public var latitude: Double
        public var longitude: Double
        /// Distance from the previous point, NM.
        public var legDistance: Double?
        public var altitude: Int?
        /// Fuel planned and minimum on board at the point, in the OFP's unit.
        public var plannedFuel: Double?
        public var minimumFuel: Double?
        /// Seconds from take-off.
        public var timeTotal: Int?
        public var stage: String?
        /// Airway or procedure the point is flown by, and whether it belongs to the SID or STAR.
        public var airway: String? = nil
        public var isProcedure: Bool? = nil
    }

    public struct Fuel: Codable, Sendable, Equatable {
        public var taxi: Double?
        public var trip: Double?
        public var contingency: Double?
        public var alternate: Double?
        public var finalReserve: Double?
        public var extra: Double?
        public var takeoff: Double?
        public var block: Double?
        public var landing: Double?
    }

    public struct Weights: Codable, Sendable, Equatable {
        public var passengers: Int?
        public var payload: Double?
        public var zeroFuel: Double?
        public var maxZeroFuel: Double?
        public var takeoff: Double?
        public var maxTakeoff: Double?
        public var landing: Double?
        public var maxLanding: Double?
    }

    /// Take-off data for the planned runway from SimBrief's performance module (TLR).
    public struct Takeoff: Codable, Sendable, Equatable {
        public var runway: String
        public var flaps: String?
        public var thrust: String?
        public var flexTemperature: Int?
        public var v1: Int?
        public var vr: Int?
        public var v2: Int?
        public var ilsFrequency: String?
    }

    public var requestID: String?
    public var generated: Date?
    public var airac: String?
    /// "kgs" or "lbs".
    public var units: String
    public var callsign: String?
    public var aircraft: String?
    public var registration: String?
    public var origin: Airport
    public var destination: Airport
    public var alternate: Airport?
    public var costIndex: Int?
    /// Initial cruise altitude, feet.
    public var initialAltitude: Int?
    public var averageTemperatureDeviation: Int?
    public var averageTropopause: Int?
    public var averageWindDirection: Int?
    public var averageWindSpeed: Int?
    /// "EGLL/0230/DVR/0370": fix and flight level pairs.
    public var stepClimbs: String?
    /// Route in ATC form: SID, waypoints and airways, STAR.
    public var route: String?
    public var sid: String?
    public var sidTransition: String?
    public var star: String?
    public var starTransition: String?
    public var routeDistance: Int?
    /// Estimated time en route, seconds.
    public var timeEnroute: Int?
    public var scheduledOut: Date?
    public var taxiOutMinutes: Double?
    public var fuel: Fuel
    public var weights: Weights
    public var takeoff: Takeoff?
    public var landingILSFrequency: String?
    /// Optional so an OFP saved before the navlog was read still loads.
    public var navlog: [NavFix]? = nil
    public var enrouteAlternates: [Airport]? = nil
    /// The ICAO flight plan as filed (FPL message).
    public var atcFlightPlan: String? = nil

    public var fixes: [NavFix] { navlog ?? [] }

    public var isPounds: Bool { units.lowercased().hasPrefix("lb") }
    /// "t" or "klb": the unit the MCDU takes weights in.
    public var massUnit: String { isPounds ? "klb" : "t" }
    public var routeTitle: String { "\(origin.icao)→\(destination.icao)" }

    /// Kilograms of a mass in the OFP's unit.
    public func kilograms(_ value: Double?) -> Double? {
        value.map { isPounds ? $0 * 0.453592 : $0 }
    }

    // MARK: Route

    /// En-route part of the route as the MCDU's AIRWAYS page takes it: the first waypoint after
    /// the SID, then "via airway (or DCT) to waypoint" legs up to the STAR.
    public var routeLegs: (start: String?, legs: [(via: String, to: String)]) {
        var tokens = (route ?? "").split(separator: " ").map(String.init).filter { !$0.isEmpty }
        if let first = tokens.first, first == sid || first == origin.icao { tokens.removeFirst() }
        if let last = tokens.last, last == star || last == destination.icao { tokens.removeLast() }
        guard let start = tokens.first else { return (nil, []) }
        var legs: [(via: String, to: String)] = []
        var index = 1
        while index + 1 < tokens.count {
            legs.append((via: tokens[index], to: tokens[index + 1]))
            index += 2
        }
        return (start, legs)
    }

    /// Step climbs after the initial level, as (fix, flight level).
    public var stepClimbList: [(fix: String, level: Int)] {
        let parts = (stepClimbs ?? "").split(separator: "/").map(String.init)
        var result: [(fix: String, level: Int)] = []
        var index = 2   // the first pair is the departure and the initial level
        while index + 1 < parts.count {
            if let level = Int(parts[index + 1]) { result.append((fix: parts[index], level: level)) }
            index += 2
        }
        return result
    }

    /// ISA temperature at the initial cruise altitude plus the average deviation, rounded.
    public var cruiseTemperature: Int? {
        guard let altitude = initialAltitude else { return nil }
        let isa = max(-56.5, 15 - 1.98 * Double(altitude) / 1000)
        return Int((isa + Double(averageTemperatureDeviation ?? 0)).rounded())
    }

    // MARK: Parsing

    public enum ParseError: Error, Equatable {
        case notJSON
        /// SimBrief answered with an error, e.g. no flight plan for that user.
        case simBrief(String)
        case missingAirports
    }

    public static func parse(_ data: Data) throws -> SimBriefOFP {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.notJSON }
        let fetch = root["fetch"] as? [String: Any]
        if let status = text(fetch?["status"]), status.lowercased() != "success" {
            throw ParseError.simBrief(status)
        }
        let params = root["params"] as? [String: Any] ?? [:]
        let general = root["general"] as? [String: Any] ?? [:]
        let atc = root["atc"] as? [String: Any] ?? [:]
        let aircraft = root["aircraft"] as? [String: Any] ?? [:]
        let fuel = root["fuel"] as? [String: Any] ?? [:]
        let weights = root["weights"] as? [String: Any] ?? [:]
        let times = root["times"] as? [String: Any] ?? [:]
        guard let origin = airport(root["origin"]), let destination = airport(root["destination"]) else {
            throw ParseError.missingAirports
        }

        var ofp = SimBriefOFP(
            requestID: text(params["request_id"]),
            generated: number(params["time_generated"]).map { Date(timeIntervalSince1970: $0) },
            airac: text(params["airac"]),
            units: text(params["units"]) ?? "kgs",
            callsign: text(atc["callsign"]) ?? [text(general["icao_airline"]), text(general["flight_number"])].compactMap { $0 }.joined(),
            aircraft: text(aircraft["icaocode"]) ?? text(aircraft["icao_code"]),
            registration: text(aircraft["reg"]),
            origin: origin,
            destination: destination,
            alternate: airport(root["alternate"]),
            costIndex: integer(general["costindex"]),
            initialAltitude: integer(general["initial_altitude"]),
            averageTemperatureDeviation: integer(general["avg_temp_dev"]),
            averageTropopause: integer(general["avg_tropopause"]),
            averageWindDirection: integer(general["avg_wind_dir"]),
            averageWindSpeed: integer(general["avg_wind_spd"]),
            stepClimbs: text(general["stepclimb_string"]),
            route: text(general["route"]),
            sid: text(general["sid_ident"]),
            sidTransition: text(general["sid_trans"]),
            star: text(general["star_ident"]),
            starTransition: text(general["star_trans"]),
            routeDistance: integer(general["route_distance"]),
            timeEnroute: integer(times["est_time_enroute"]),
            scheduledOut: number(times["sched_out"]).map { Date(timeIntervalSince1970: $0) },
            taxiOutMinutes: number(times["taxi_out"]).map { $0 / 60 },
            fuel: Fuel(taxi: number(fuel["taxi"]), trip: number(fuel["enroute_burn"]),
                       contingency: number(fuel["contingency"]), alternate: number(fuel["alternate_burn"]),
                       finalReserve: number(fuel["reserve"]), extra: number(fuel["extra"]),
                       takeoff: number(fuel["plan_takeoff"]), block: number(fuel["plan_ramp"]),
                       landing: number(fuel["plan_landing"])),
            weights: Weights(passengers: integer(weights["pax_count"]), payload: number(weights["payload"]),
                             zeroFuel: number(weights["est_zfw"]), maxZeroFuel: number(weights["max_zfw"]),
                             takeoff: number(weights["est_tow"]), maxTakeoff: number(weights["max_tow"]),
                             landing: number(weights["est_ldw"]), maxLanding: number(weights["max_ldw"])),
            takeoff: nil,
            landingILSFrequency: nil)
        if ofp.callsign?.isEmpty == true { ofp.callsign = nil }

        if let navlog = root["navlog"] as? [String: Any] {
            ofp.navlog = runways(navlog["fix"]).compactMap { fix in
                guard let ident = text(fix["ident"]), let latitude = number(fix["pos_lat"]),
                      let longitude = number(fix["pos_long"]) else { return nil }
                return NavFix(ident: ident, type: text(fix["type"]), latitude: latitude, longitude: longitude,
                              legDistance: number(fix["distance"]), altitude: integer(fix["altitude_feet"]),
                              plannedFuel: number(fix["fuel_plan_onboard"]), minimumFuel: number(fix["fuel_min_onboard"]),
                              timeTotal: integer(fix["time_total"]), stage: text(fix["stage"]),
                              airway: text(fix["via_airway"]), isProcedure: text(fix["is_sid_star"]).map { $0 == "1" })
            }
        }
        ofp.enrouteAlternates = runways(root["enroute_altn"]).compactMap { airport($0) }
        ofp.atcFlightPlan = text((root["atc"] as? [String: Any])?["flightplan_text"])

        // Performance (TLR): the planned runway's take-off data and the landing runway's ILS.
        if let tlr = root["tlr"] as? [String: Any] {
            if let takeoff = tlr["takeoff"] as? [String: Any] {
                let planned = text((takeoff["conditions"] as? [String: Any])?["planned_runway"]) ?? origin.runway
                if let runway = runways(takeoff["runway"]).first(where: { text($0["identifier"]) == planned }), let id = planned {
                    ofp.takeoff = Takeoff(runway: id, flaps: text(runway["flap_setting"]), thrust: text(runway["thrust_setting"]),
                                          flexTemperature: integer(runway["flex_temperature"]),
                                          v1: integer(runway["speeds_v1"]), vr: integer(runway["speeds_vr"]),
                                          v2: integer(runway["speeds_v2"]), ilsFrequency: text(runway["ils_frequency"]))
                }
            }
            if let landing = tlr["landing"] as? [String: Any] {
                let planned = text((landing["conditions"] as? [String: Any])?["planned_runway"]) ?? destination.runway
                ofp.landingILSFrequency = runways(landing["runway"]).first { text($0["identifier"]) == planned }
                    .flatMap { text($0["ils_frequency"]) }
            }
        }
        return ofp
    }

    private static func airport(_ value: Any?) -> Airport? {
        guard let object = value as? [String: Any], let icao = text(object["icao_code"]) else { return nil }
        return Airport(icao: icao, name: text(object["name"]), elevation: integer(object["elevation"]),
                       runway: text(object["plan_rwy"]), transitionAltitude: integer(object["trans_alt"]),
                       transitionLevel: integer(object["trans_level"]), metar: text(object["metar"]),
                       latitude: number(object["pos_lat"]), longitude: number(object["pos_long"]),
                       weatherCategory: text(object["metar_category"])?.lowercased(), taf: text(object["taf"]),
                       atis: messages(object["atis"], keys: ["message", "text"]),
                       notams: messages(object["notam"], keys: ["notam_text", "text", "message"]))
    }

    /// Texts from a field that may be a string, a list of strings or a list of objects.
    private static func messages(_ value: Any?, keys: [String]) -> [String]? {
        var result: [String] = []
        let items: [Any] = (value as? [Any]) ?? (value.map { [$0] } ?? [])
        for item in items {
            if let string = text(item) {
                result.append(string)
            } else if let object = item as? [String: Any] {
                if let string = keys.lazy.compactMap({ text(object[$0]) }).first {
                    let id = text(object["notam_id"]) ?? text(object["network"])
                    result.append(id.map { "\($0): \(string)" } ?? string)
                }
            }
        }
        return result.isEmpty ? nil : result
    }

    private static func runways(_ value: Any?) -> [[String: Any]] {
        if let list = value as? [[String: Any]] { return list }
        if let single = value as? [String: Any] { return [single] }
        return []
    }

    /// Non-empty text; SimBrief's `{}` for "nothing" reads as nil.
    static func text(_ value: Any?) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    static func number(_ value: Any?) -> Double? {
        guard let text = text(value) else { return nil }
        // "P004" / "M012" style signs appear in a few fields.
        let cleaned = text.replacingOccurrences(of: "P", with: "").replacingOccurrences(of: "M", with: "-")
        return Double(cleaned)
    }

    static func integer(_ value: Any?) -> Int? {
        number(value).map { Int($0.rounded()) }
    }

    /// The fetch URL: a numeric pilot ID goes as `userid`, anything else as `username`.
    public static func fetchURL(user: String) -> URL? {
        let trimmed = user.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let key = trimmed.allSatisfy(\.isNumber) ? "userid" : "username"
        var components = URLComponents(string: "https://www.simbrief.com/api/xml.fetcher.php")
        components?.queryItems = [URLQueryItem(name: key, value: trimmed), URLQueryItem(name: "json", value: "1")]
        return components?.url
    }
}

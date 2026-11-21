import Foundation

// Simulated ATC built from the flight plan: every exchange a crew would have from the clearance
// to the stand, in ICAO phraseology, with what the pilot says, what the controller answers and
// the read-back. Nothing is heard or sent anywhere: the pilot speaks (or taps), the app plays the
// controller. Each line has a written form and a spoken form for the speech synthesiser
// ("FL350" is read "flight level three five zero").

/// Text as shown and as spoken.
public struct Phrase: Sendable, Equatable, ExpressibleByStringLiteral {
    public var display: String
    public var spoken: String

    public init(_ display: String, spoken: String? = nil) {
        self.display = display
        self.spoken = spoken ?? display
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public static func + (lhs: Phrase, rhs: Phrase) -> Phrase {
        Phrase(lhs.display + rhs.display, spoken: lhs.spoken + rhs.spoken)
    }

    /// Joined with ", " (or another separator), skipping nils.
    public static func list(_ parts: [Phrase?], separator: String = ", ") -> Phrase {
        let present = parts.compactMap { $0 }
        return Phrase(present.map(\.display).joined(separator: separator),
                      spoken: present.map(\.spoken).joined(separator: separator))
    }
}

/// Radiotelephony: how numbers, levels, runways and names are said on the radio.
public enum Radio {
    static let digitWords: [Character: String] = [
        "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four",
        "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "niner",
    ]
    static let alphabet = ["A": "Alpha", "B": "Bravo", "C": "Charlie", "D": "Delta", "E": "Echo", "F": "Foxtrot",
                           "G": "Golf", "H": "Hotel", "I": "India", "J": "Juliett", "K": "Kilo", "L": "Lima",
                           "M": "Mike", "N": "November", "O": "Oscar", "P": "Papa", "Q": "Quebec", "R": "Romeo",
                           "S": "Sierra", "T": "Tango", "U": "Uniform", "V": "Victor", "W": "Whiskey", "X": "X-ray",
                           "Y": "Yankee", "Z": "Zulu"]

    /// "4521" → "four five two one". Other characters are kept.
    public static func digits(_ text: String) -> String {
        text.map { digitWords[$0] ?? String($0) }.joined(separator: " ")
    }

    public static func letter(_ letter: String) -> Phrase {
        let upper = letter.uppercased()
        return Phrase(upper, spoken: alphabet[upper] ?? upper)
    }

    /// FL350 / "flight level three five zero".
    public static func flightLevel(feet: Int) -> Phrase {
        let level = (feet + 50) / 100
        let text = String(format: "%03d", level)
        return Phrase("FL\(text)", spoken: "flight level \(digits(text))")
    }

    /// "5000 ft" / "five thousand feet"; "4500 ft" / "four thousand five hundred feet".
    public static func altitude(feet: Int) -> Phrase {
        let rounded = (feet + 50) / 100 * 100
        let thousands = rounded / 1000, hundreds = rounded % 1000 / 100
        var words: [String] = []
        if thousands > 0 { words.append("\(digits(String(thousands))) thousand") }
        if hundreds > 0 { words.append("\(digits(String(hundreds))) hundred") }
        return Phrase("\(rounded) ft", spoken: words.joined(separator: " ") + " feet")
    }

    /// A level or an altitude depending on the transition: FL above it, feet below.
    public static func level(feet: Int, transitionAltitude: Int) -> Phrase {
        feet > transitionAltitude ? flightLevel(feet: feet) : altitude(feet: feet)
    }

    /// "36L" / "three six left".
    public static func runway(_ runway: String) -> Phrase {
        let upper = runway.uppercased()
        let number = String(upper.prefix { $0.isNumber })
        let side: String
        switch upper.dropFirst(number.count).first {
        case "L": side = " left"
        case "R": side = " right"
        case "C": side = " center"
        default: side = ""
        }
        return Phrase(upper, spoken: digits(number) + side)
    }

    /// "118.705" / "one one eight decimal seven zero five".
    public static func frequency(_ frequency: String) -> Phrase {
        let parts = frequency.split(separator: ".", maxSplits: 1)
        let spoken = parts.map { digits(String($0)) }.joined(separator: " decimal ")
        return Phrase(frequency, spoken: spoken)
    }

    /// "QNH 1013" / "QNH one zero one three".
    public static func qnh(_ hectopascals: Int) -> Phrase {
        Phrase("QNH \(hectopascals)", spoken: "QNH \(digits(String(hectopascals)))")
    }

    /// "240/10" / "two four zero degrees, one zero knots".
    public static func wind(direction: Int?, speed: Int?) -> Phrase? {
        guard let direction, let speed else { return nil }
        let heading = String(format: "%03d", direction)
        return Phrase("wind \(heading)/\(speed) kt",
                      spoken: "wind \(digits(heading)) degrees, \(digits(String(speed))) knots")
    }

    /// Procedure names: "NANDO1A" / "NANDO one Alpha".
    public static func procedure(_ name: String) -> Phrase {
        let upper = name.uppercased()
        guard let digitIndex = upper.firstIndex(where: \.isNumber) else { return Phrase(upper) }
        let word = String(upper[..<digitIndex])
        let rest = upper[digitIndex...]
        let spokenRest = rest.map { character -> String in
            if let digit = digitWords[character] { return digit }
            return alphabet[String(character)] ?? String(character)
        }.joined(separator: " ")
        return Phrase(upper, spoken: "\(word.capitalized) \(spokenRest)")
    }

    /// Radio callsign of a flight: "IBE3742" / "Iberia three seven four two". Unknown airlines
    /// are spelled out.
    public static func callsign(_ callsign: String) -> Phrase {
        let upper = callsign.uppercased().replacingOccurrences(of: " ", with: "")
        let prefix = String(upper.prefix { $0.isLetter })
        let number = String(upper.dropFirst(prefix.count))
        if prefix.count == 3, let telephony = telephony[prefix] {
            return Phrase("\(telephony) \(number)", spoken: "\(telephony) \(digits(number))")
        }
        let spelled = upper.map { character -> String in
            digitWords[character] ?? alphabet[String(character)] ?? String(character)
        }.joined(separator: " ")
        return Phrase(upper, spoken: spelled)
    }

    /// ICAO airline designators and their radio callsigns, mostly European operators.
    static let telephony: [String: String] = [
        "IBE": "Iberia", "IBS": "Iberexpress", "VLG": "Vueling", "AEA": "Europa", "ANE": "Air Nostrum",
        "BTI": "Air Baltic", "RYR": "Ryanair", "EZY": "Easy", "EJU": "Alpine", "EZS": "Topswiss", "DLH": "Lufthansa",
        "BAW": "Speedbird", "AFR": "Airfrans", "KLM": "KLM", "SWR": "Swiss", "AUA": "Austrian", "TAP": "Air Portugal",
        "ITY": "Itarrow", "SAS": "Scandinavian", "FIN": "Finnair", "EWG": "Eurowings", "WZZ": "Wizz Air",
        "TVF": "France Soleil", "TRA": "Transavia", "VOE": "Volotea", "BEL": "Beeline", "AEE": "Aegean",
        "THY": "Turkish", "UAE": "Emirates", "QTR": "Qatari", "ETD": "Etihad", "AAL": "American", "UAL": "United",
        "DAL": "Delta", "JBU": "Jetblue", "SWA": "Southwest", "ACA": "Air Canada", "LAN": "Lan", "AVA": "Avianca",
        "AMX": "Aeromexico", "PLM": "Air Pullmantur", "IBB": "Binter", "NOZ": "Nordic", "NAX": "Nor Shuttle",
        "LOT": "Lot", "CSA": "CSA", "EIN": "Shamrock", "SXS": "Sunexpress", "CFG": "Condor", "TOM": "Tomjet",
    ]
}

extension Radio {
    /// Name the ATC units of an airport go by: "Madrid" for LEMD ("Madrid Delivery"). Known
    /// airports first, then the airport name without the usual words, then the ICAO code.
    public static func city(icao: String, airportName: String?) -> String {
        if let known = cities[icao.uppercased()] { return known }
        let skip: Set<String> = ["INTL", "INTERNATIONAL", "AIRPORT", "AEROPUERTO", "AEROPORT", "AEROPORTO", "FLUGHAFEN",
                                 "REGIONAL", "MUNICIPAL", "FIELD", "THE", "DE", "DEL", "LA", "EL", "OF", "AIR", "BASE"]
        let words = (airportName ?? "")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { !skip.contains($0.uppercased()) && $0.allSatisfy(\.isLetter) }
        guard let first = words.first else { return icao.uppercased() }
        return first.prefix(1).uppercased() + first.dropFirst().lowercased()
    }

    static let cities: [String: String] = [
        "LEMD": "Madrid", "LEBL": "Barcelona", "LEPA": "Palma", "LEMG": "Malaga", "LEAL": "Alicante", "LEVC": "Valencia",
        "LEZL": "Sevilla", "LEBB": "Bilbao", "LEST": "Santiago", "LEVX": "Vigo", "LEAS": "Asturias", "LEGR": "Granada",
        "LEIB": "Ibiza", "LEMH": "Menorca", "LEGE": "Girona", "LERS": "Reus", "LEZG": "Zaragoza", "LESO": "San Sebastian",
        "LEXJ": "Santander", "LECO": "La Coruna", "LEJR": "Jerez", "LEMI": "Murcia", "LEVD": "Valladolid",
        "GCLP": "Gran Canaria", "GCTS": "Tenerife Sur", "GCXO": "Tenerife Norte", "GCRR": "Lanzarote",
        "GCFV": "Fuerteventura", "GCLA": "La Palma", "LPPT": "Lisboa", "LPPR": "Porto", "LPFR": "Faro",
        "LPMA": "Madeira", "LFPG": "De Gaulle", "LFPO": "Orly", "LFMN": "Nice", "LFLL": "Lyon", "LFML": "Marseille",
        "LFBO": "Toulouse", "EGLL": "Heathrow", "EGKK": "Gatwick", "EGSS": "Stansted", "EGCC": "Manchester",
        "EDDF": "Frankfurt", "EDDM": "Munich", "EDDB": "Berlin", "EDDL": "Dusseldorf", "EDDH": "Hamburg",
        "EHAM": "Schiphol", "EBBR": "Brussels", "LSZH": "Zurich", "LSGG": "Geneva", "LOWW": "Wien", "LIRF": "Roma",
        "LIMC": "Milano", "LIPZ": "Venezia", "EIDW": "Dublin", "EKCH": "Kastrup", "ESSA": "Stockholm",
        "ENGM": "Oslo", "EFHK": "Helsinki", "LGAV": "Athens", "LTFM": "Istanbul", "EPWA": "Warszawa",
        "LKPR": "Praha", "LHBP": "Budapest", "GMMN": "Casablanca", "KJFK": "Kennedy", "KLAX": "Los Angeles",
        "KORD": "Chicago", "KATL": "Atlanta", "KMIA": "Miami", "KSFO": "San Francisco",
    ]
}

public struct RadioCall: Sendable, Equatable, Identifiable {
    public enum Speaker: String, Sendable { case pilot, controller }

    public let id: String
    public let speaker: Speaker
    public let text: Phrase

    public init(id: String, speaker: Speaker, text: Phrase) {
        self.id = id
        self.speaker = speaker
        self.text = text
    }
}

/// Something the clearance asks the crew to set, that the app can set for them.
public enum ATCAction: Sendable, Equatable {
    case squawk(String)
    case altitude(Int)
    case qnh(Int)
}

/// When an exchange happens. Pilot calls are suggested at that moment; controller calls play
/// by themselves then, if the option is on.
public enum ATCTrigger: Sendable, Equatable {
    /// Whenever the pilot is ready (on the ground, before moving).
    case manual
    /// Airborne and this high above the departure field.
    case airborne(aboveField: Double)
    /// Climbing through this altitude.
    case climbingThrough(Double)
    /// Within this distance of the top of descent.
    case nearTopOfDescent(miles: Double)
    /// Descending through this altitude after the cruise.
    case descendingThrough(Double)
    /// Within this distance of the destination.
    case distanceToGo(Double)
    /// Below this height over the destination, on the approach.
    case heightBelow(Double)
    /// Turned off the runway after landing.
    case runwayVacated
}

public struct ATCExchange: Sendable, Equatable, Identifiable {
    public enum Phase: String, Sendable, CaseIterable {
        case clearance, ground, tower, departure, enroute, arrival, approach, landing, taxiIn

        public var title: String {
            switch self {
            case .clearance: return "Autorización"
            case .ground: return "Rodaje"
            case .tower: return "Torre"
            case .departure: return "Salida"
            case .enroute: return "En ruta"
            case .arrival: return "Llegada"
            case .approach: return "Aproximación"
            case .landing: return "Aterrizaje"
            case .taxiIn: return "Rodaje a puesto"
            }
        }
    }

    public let id: String
    public let phase: Phase
    /// "Madrid Delivery".
    public let station: String
    /// Known frequency of the station, if the briefing has it.
    public let frequency: String?
    /// What it is and what to do, in Spanish.
    public let title: String
    public let note: String
    public let calls: [RadioCall]
    public let trigger: ATCTrigger
    public let actions: [ATCAction]

    /// The controller speaks first (a hand-off, a clearance on the ATC's initiative).
    public var startsWithController: Bool { calls.first?.speaker == .controller }
}

/// What the script is made from: the OFP and the departure briefing, as plain values.
public struct ATCInput: Sendable, Equatable {
    public var callsign: String
    public var aircraftType: String = "A320"
    public var origin: String
    public var originCity: String
    public var destination: String
    public var destinationCity: String
    public var departureRunway: String?
    public var arrivalRunway: String?
    public var sid: String?
    public var star: String?
    /// Feet.
    public var initialClimb: Int
    public var cruise: Int
    public var squawk: String
    public var departureATIS: String?
    public var arrivalATIS: String?
    public var departureQNH: Int?
    public var arrivalQNH: Int?
    public var departureWind: (direction: Int?, speed: Int?) = (nil, nil)
    public var arrivalWind: (direction: Int?, speed: Int?) = (nil, nil)
    public var departureFrequency: String?
    public var hasILS: Bool = true
    public var transitionAltitude: Int = 6000
    /// Feet.
    public var destinationElevation: Int = 0

    public init(callsign: String, origin: String, originCity: String, destination: String, destinationCity: String,
                initialClimb: Int, cruise: Int, squawk: String) {
        self.callsign = callsign
        self.origin = origin
        self.originCity = originCity
        self.destination = destination
        self.destinationCity = destinationCity
        self.initialClimb = initialClimb
        self.cruise = cruise
        self.squawk = squawk
    }

    public static func == (lhs: ATCInput, rhs: ATCInput) -> Bool {
        lhs.callsign == rhs.callsign && lhs.origin == rhs.origin && lhs.destination == rhs.destination
            && lhs.departureRunway == rhs.departureRunway && lhs.arrivalRunway == rhs.arrivalRunway
            && lhs.sid == rhs.sid && lhs.star == rhs.star && lhs.initialClimb == rhs.initialClimb
            && lhs.cruise == rhs.cruise && lhs.squawk == rhs.squawk && lhs.departureATIS == rhs.departureATIS
            && lhs.arrivalATIS == rhs.arrivalATIS && lhs.departureQNH == rhs.departureQNH
            && lhs.arrivalQNH == rhs.arrivalQNH && lhs.departureFrequency == rhs.departureFrequency
            && lhs.hasILS == rhs.hasILS && lhs.transitionAltitude == rhs.transitionAltitude
            && lhs.departureWind.direction == rhs.departureWind.direction && lhs.departureWind.speed == rhs.departureWind.speed
            && lhs.arrivalWind.direction == rhs.arrivalWind.direction && lhs.arrivalWind.speed == rhs.arrivalWind.speed
            && lhs.destinationElevation == rhs.destinationElevation
    }
}

public enum ATCScript {
    /// Every exchange of the flight, in order.
    public static func make(_ input: ATCInput) -> [ATCExchange] {
        // Joins parts into one phrase (a list, not a chain of +: long chains of literals are
        // slow for the type checker).
        func p(_ parts: Phrase...) -> Phrase {
            Phrase(parts.map(\.display).joined(), spoken: parts.map(\.spoken).joined())
        }
        func comma(_ phrase: Phrase?) -> Phrase {
            phrase.map { p(", ", $0) } ?? ""
        }

        let cs = Radio.callsign(input.callsign)
        let ta = input.transitionAltitude
        let depRunway: Phrase = input.departureRunway.map(Radio.runway) ?? "as assigned"
        let arrRunway: Phrase = input.arrivalRunway.map(Radio.runway) ?? "as assigned"
        let initial = Radio.level(feet: input.initialClimb, transitionAltitude: ta)
        let cruise = Radio.flightLevel(feet: input.cruise)
        // Intermediate level from departure before the en-route centre gives the cruise.
        let intermediateFeet = input.cruise > 16_000 ? max(input.initialClimb, min(input.cruise, 15_000)) : input.cruise
        let intermediate = Radio.level(feet: intermediateFeet, transitionAltitude: ta)
        let handoffAltitude = Double(min(intermediateFeet, 12_000))
        // First descent from the en-route centre, then the approach altitude.
        let descentFeet = min(input.cruise, max(10_000, input.destinationElevation + 7_000))
        let descent = Radio.flightLevel(feet: descentFeet)
        let approachFeet = max(3_000, (input.destinationElevation + 3_500) / 1_000 * 1_000)
        let approachAltitude = Radio.altitude(feet: approachFeet)
        let squawk = Phrase(input.squawk, spoken: Radio.digits(input.squawk))
        let sid = input.sid.map(Radio.procedure)
        let star = input.star.map(Radio.procedure)
        let depATIS = Radio.letter(input.departureATIS ?? "A")
        let arrATIS = Radio.letter(input.arrivalATIS ?? "B")
        let approachType = input.hasILS ? Phrase("ILS") : Phrase("RNP", spoken: "R N P")
        let depWind = Radio.wind(direction: input.departureWind.direction, speed: input.departureWind.speed)
        let arrWind = Radio.wind(direction: input.arrivalWind.direction, speed: input.arrivalWind.speed)
        let depQNH = input.departureQNH.map(Radio.qnh)
        let arrQNH = input.arrivalQNH.map(Radio.qnh)
        let departureFrequency = input.departureFrequency.flatMap { $0.isEmpty ? nil : $0 }

        func contact(_ name: String, _ frequency: String?) -> Phrase {
            p(Phrase("contact " + name), frequency.map { p(" ", Radio.frequency($0)) } ?? "")
        }

        var exchanges: [ATCExchange] = []
        func add(_ phase: ATCExchange.Phase, _ station: String, frequency: String? = nil, title: String, note: String,
                 trigger: ATCTrigger = .manual, actions: [ATCAction] = [], _ calls: [(RadioCall.Speaker, Phrase)]) {
            let id = String(format: "%02d", exchanges.count + 1)
            let radioCalls = calls.enumerated().map { offset, call in
                RadioCall(id: "\(id).\(offset)", speaker: call.0, text: call.1)
            }
            exchanges.append(ATCExchange(id: id, phase: phase, station: station, frequency: frequency, title: title,
                                         note: note, calls: radioCalls, trigger: trigger, actions: actions))
        }

        let delivery = input.originCity + " Delivery"
        let ground = input.originCity + " Ground"
        let tower = input.originCity + " Tower"
        let departure = input.originCity + " Departure"
        let control1 = input.originCity + " Control"
        let control2 = input.destinationCity + " Control"
        let approach = input.destinationCity + " Approach"
        let arrivalTower = input.destinationCity + " Tower"
        let arrivalGround = input.destinationCity + " Ground"
        let destination = Phrase(input.destinationCity)

        // MARK: Clearance
        let route = sid.map { p("via ", $0, " departure") } ?? "via flight planned route"
        add(.clearance, delivery, title: "Autorización de ruta",
            note: "Con el ATIS escuchado, pide la autorización IFR. Colaciona todo: destino, salida, pista, altitud y código. Después pon el código en el transpondedor y la altitud en el FCU.",
            actions: [.squawk(input.squawk), .altitude(input.initialClimb)], [
                (.pilot, p(Phrase(delivery), ", ", cs, Phrase(", " + input.aircraftType), ", information ", depATIS,
                           ", request IFR clearance to ", destination, ".")),
                (.controller, p(cs, ", cleared to ", destination, " ", route, ", runway ", depRunway, ", climb ", initial,
                                ", squawk ", squawk, ".")),
                (.pilot, p("Cleared to ", destination, " ", route, ", runway ", depRunway, ", climb ", initial,
                           ", squawk ", squawk, ", ", cs, ".")),
                (.controller, p(cs, ", readback correct. Contact Ground when ready to push.")),
            ])

        // MARK: Ground
        add(.ground, ground, title: "Remolque y puesta en marcha",
            note: "Puertas cerradas y preparado: pide el pushback. Beacon encendido antes de que empuje el tractor.", [
                (.pilot, p(Phrase(ground), ", ", cs, ", stand, ready for push back and start up.")),
                (.controller, p(cs, ", push back and start up approved.")),
                (.pilot, p("Push back and start up approved, ", cs, ".")),
            ])
        add(.ground, ground, title: "Rodaje al punto de espera",
            note: "Motores arrancados y after start hecho: pide rodaje. La ruta de rodaje exacta está en la carta del aeropuerto; colaciona siempre la pista y el punto de espera.",
            actions: input.departureQNH.map { [ATCAction.qnh($0)] } ?? [], [
                (.pilot, p(cs, ", request taxi.")),
                (.controller, p(cs, ", taxi to holding point runway ", depRunway, comma(depQNH), ". Contact Tower when ready.")),
                (.pilot, p("Taxi to holding point runway ", depRunway, comma(depQNH), ", ", cs, ".")),
            ])

        // MARK: Tower
        add(.tower, tower, title: "Listos para salir",
            note: "En el punto de espera y con el before take-off hecho. «Line up and wait»: entra en pista y espera, no despegues.", [
                (.pilot, p(Phrase(tower), ", ", cs, ", holding point runway ", depRunway, ", ready for departure.")),
                (.controller, p(cs, ", line up and wait runway ", depRunway, ".")),
                (.pilot, p("Line up and wait runway ", depRunway, ", ", cs, ".")),
            ])
        add(.tower, tower, title: "Autorizado a despegar",
            note: "Ya alineado. La autorización de despegue se colaciona siempre con la pista.", [
                (.controller, p(cs, comma(depWind), ", runway ", depRunway, ", cleared for take-off.")),
                (.pilot, p("Cleared for take-off runway ", depRunway, ", ", cs, ".")),
            ])
        add(.tower, tower, title: "Cambio a salidas",
            note: "Ya en el aire, la torre te pasa a la dependencia de salidas.", trigger: .airborne(aboveField: 1000), [
                (.controller, p(cs, ", ", contact(departure, departureFrequency), ". Good bye.")),
                (.pilot, p(departureFrequency.map(Radio.frequency) ?? Phrase(departure), ", ", cs, ", good bye.")),
            ])

        // MARK: Departure
        add(.departure, departure, frequency: departureFrequency, title: "Primer contacto con salidas",
            note: "Indica la altitud que pasas (léela del altímetro), la autorizada y la salida que vuelas. Te autorizarán a un nivel más alto.",
            trigger: .airborne(aboveField: 1500), actions: [.altitude(intermediateFeet)], [
                (.pilot, p(Phrase(departure), ", ", cs, ", passing ", Phrase("(altitud actual)", spoken: "two thousand five hundred feet"),
                           ", climbing ", initial, comma(sid), ".")),
                (.controller, p(cs, Phrase(", " + departure), ", radar contact, climb ", intermediate, ".")),
                (.pilot, p("Climb ", intermediate, ", ", cs, ".")),
            ])
        add(.departure, departure, title: "Cambio a control en ruta",
            note: "Saliendo del área terminal te transfieren al centro de control.",
            trigger: .climbingThrough(handoffAltitude), [
                (.controller, p(cs, ", ", contact(control1, nil), ". Good day.")),
                (.pilot, p(Phrase(control1), ", ", cs, ", good day.")),
            ])

        // MARK: En route
        add(.enroute, control1, title: "Ascenso a crucero",
            note: "Primer contacto con el centro: nivel que pasas y autorizado. Te darán el nivel de crucero del plan.",
            trigger: .climbingThrough(handoffAltitude + 500), actions: [.altitude(input.cruise)], [
                (.pilot, p(Phrase(control1), ", ", cs, ", climbing ", intermediate, ".")),
                (.controller, p(cs, Phrase(", " + control1), ", identified, climb ", cruise, ".")),
                (.pilot, p("Climb ", cruise, ", ", cs, ".")),
            ])
        if control2 != control1 {
            add(.enroute, control1, title: "Cambio de centro",
                note: "Más adelante en la ruta pasas al centro de control del destino.", trigger: .distanceToGo(200), [
                    (.controller, p(cs, ", ", contact(control2, nil), ". Good day.")),
                    (.pilot, p(Phrase(control2), ", ", cs, ", good day.")),
                ])
            add(.enroute, control2, title: "Contacto con el nuevo centro",
                note: "Solo indicativo y nivel.", trigger: .distanceToGo(195), [
                    (.pilot, p(Phrase(control2), ", ", cs, ", ", cruise, ".")),
                    (.controller, p(cs, Phrase(", " + control2), ", identified, maintain ", cruise, ".")),
                ])
        }

        // MARK: Arrival
        let arrivalRoute = star.map { p(", cleared ", $0, " arrival") } ?? ""
        add(.arrival, control2, title: "Pide el descenso",
            note: "Unos minutos antes del TOD pide descenso. Te autorizarán a un nivel y a la llegada (STAR) a la pista en uso.",
            trigger: .nearTopOfDescent(miles: 15), actions: [.altitude(descentFeet)], [
                (.pilot, p(Phrase(control2), ", ", cs, ", request descent.")),
                (.controller, p(cs, ", descend ", descent, arrivalRoute, ", runway ", arrRunway, ".")),
                (.pilot, p("Descend ", descent, arrivalRoute, ", runway ", arrRunway, ", ", cs, ".")),
            ])
        add(.arrival, control2, title: "Cambio a aproximación",
            note: "Bajando, te pasan a la dependencia de aproximación del destino.",
            trigger: .descendingThrough(Double(descentFeet) + 2_000), [
                (.controller, p(cs, ", ", contact(approach, nil), ". Good day.")),
                (.pilot, p(Phrase(approach), ", ", cs, ", good day.")),
            ])

        // MARK: Approach
        add(.approach, approach, title: "Primer contacto con aproximación",
            note: "Indica nivel, llegada y la información ATIS del destino. Te bajarán a altitud con el QNH: cámbialo en el BARO.",
            trigger: .descendingThrough(Double(descentFeet) + 1_500),
            actions: [.altitude(approachFeet)] + (input.arrivalQNH.map { [ATCAction.qnh($0)] } ?? []), [
                (.pilot, p(Phrase(approach), ", ", cs, ", descending ", descent, comma(star), ", information ", arrATIS, ".")),
                (.controller, p(cs, Phrase(", " + approach), ", descend altitude ", approachAltitude, comma(arrQNH),
                                ", expect ", approachType, " approach runway ", arrRunway, ".")),
                (.pilot, p("Descend altitude ", approachAltitude, comma(arrQNH), ", expect ", approachType, " runway ",
                           arrRunway, ", ", cs, ".")),
            ])
        add(.approach, approach, title: "Autorizado a la aproximación",
            note: "Con el avión encarado a la final, te autorizan a la aproximación. Arma LOC y APPR cuando corresponda.",
            trigger: .distanceToGo(25), [
                (.controller, p(cs, ", cleared ", approachType, " approach runway ", arrRunway, ", report established.")),
                (.pilot, p("Cleared ", approachType, " approach runway ", arrRunway, ", wilco, ", cs, ".")),
            ])
        add(.approach, approach, title: "Establecido",
            note: "Establecido en el localizador (o en la final), lo notificas y te pasan a torre.",
            trigger: .heightBelow(3_500), [
                (.pilot, p(cs, Phrase(input.hasILS ? ", established localizer runway " : ", established final runway "), arrRunway, ".")),
                (.controller, p(cs, ", ", contact(arrivalTower, nil), ".")),
                (.pilot, p(Phrase(arrivalTower), ", ", cs, ".")),
            ])

        // MARK: Landing
        add(.landing, arrivalTower, title: "Contacto con torre",
            note: "Indicativo, aproximación y pista. Torre te dará la autorización de aterrizaje cuando la pista esté libre.",
            trigger: .heightBelow(3_000), [
                (.pilot, p(Phrase(arrivalTower), ", ", cs, ", ", approachType, " runway ", arrRunway, ".")),
                (.controller, p(cs, Phrase(", " + arrivalTower), ", continue approach, number one.")),
            ])
        add(.landing, arrivalTower, title: "Autorizado a aterrizar",
            note: "Sin esta autorización no se aterriza: a 500 ft sin ella, motor y al aire. Se colaciona con la pista.",
            trigger: .heightBelow(1_800), [
                (.controller, p(cs, comma(arrWind), ", runway ", arrRunway, ", cleared to land.")),
                (.pilot, p("Cleared to land runway ", arrRunway, ", ", cs, ".")),
            ])

        // MARK: Taxi in
        add(.taxiIn, arrivalTower, title: "Pista libre",
            note: "Al dejar la pista, torre te pasa a rodadura.", trigger: .runwayVacated, [
                (.controller, p(cs, ", ", contact(arrivalGround, nil), ".")),
                (.pilot, p(Phrase(arrivalGround), ", ", cs, ".")),
            ])
        add(.taxiIn, arrivalGround, title: "Rodaje al puesto",
            note: "Pista libre: pide rodaje al puesto. La ruta exacta está en la carta del aeropuerto.", trigger: .runwayVacated, [
                (.pilot, p(Phrase(arrivalGround), ", ", cs, ", runway vacated, request taxi to stand.")),
                (.controller, p(cs, ", taxi to stand via the published taxi route.")),
                (.pilot, p("Taxi to stand, ", cs, ".")),
            ])
        return exchanges
    }

    /// A plausible squawk when the briefing has none: four octal digits, never one of the
    /// special codes, the same for the same flight.
    public static func squawk(for seed: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        var code = ""
        for _ in 0..<4 {
            code.append(Character(String(hash % 8)))
            hash /= 8
        }
        if code.first == "0" { code.replaceSubrange(code.startIndex...code.startIndex, with: "4") }
        return ["7500", "7600", "7700", "2000", "7000", "1200"].contains(code) ? "4521" : code
    }
}

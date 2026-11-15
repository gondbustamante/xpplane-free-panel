import Foundation

/// An order to the pilot monitoring, as recognised from speech, and the answer the PM gives.
public struct VoiceCommand: Equatable, Sendable {
    public struct Target: Equatable, Sendable {
        public let control: String
        public let position: String

        public init(_ control: String, _ position: String) {
            self.control = control
            self.position = position
        }
    }

    public enum Action: Equatable, Sendable {
        /// Overhead or pedestal controls to their position.
        case set([Target])
        case gear(down: Bool)
        /// An FCU push button (AP1, AP2, A/THR).
        case fcu(String)
        case apuStart
        /// A flow to run, by procedure id.
        case flow(String)
    }

    public let action: Action
    /// What the pilot monitoring answers, in standard English phraseology.
    public let readback: String

    public init(_ action: Action, readback: String) {
        self.action = action
        self.readback = readback
    }
}

/// Turns what the pilot said, in English or Spanish, into a `VoiceCommand`. Words are reduced to
/// a small vocabulary first, so "luces de aterrizaje encendidas" and "landing lights on" read
/// the same, and the speech recogniser's spellings of numbers ("one", "1", "won") too.
public enum VoiceCommandParser {
    public static func parse(_ text: String) -> VoiceCommand? {
        let words = normalize(text)
        guard !words.isEmpty else { return nil }
        let set = Set(words)
        func has(_ items: String...) -> Bool { items.allSatisfy(set.contains) }
        func any(_ items: String...) -> Bool { items.contains(where: set.contains) }
        let on = any("on")
        let off = any("off")

        // Flows first: "after landing" must not read as the landing lights.
        let flows: [(words: [String], id: String, name: String, needsFlowWord: Bool)] = [
            (["after", "takeoff"], "after_takeoff_flow", "AFTER TAKEOFF", false),
            (["after", "landing"], "after_landing_flow", "AFTER LANDING", false),
            (["after", "start"], "after_start_flow", "AFTER START", false),
            (["before", "start"], "before_start_flow", "BEFORE START", false),
            (["lineup"], "line_up_flow", "LINE UP", false),
            (["parking"], "parking_flow", "PARKING", false),
            (["climb"], "climb_flow", "CLIMB", true),
            (["descent"], "descent_flow", "DESCENT", true),
        ]
        for flow in flows where flow.words.allSatisfy(set.contains) && (!flow.needsFlowWord || set.contains("flow")) {
            return VoiceCommand(.flow(flow.id), readback: "\(flow.name) FLOW")
        }

        if set.contains("gear") {
            if any("up", "retract") { return VoiceCommand(.gear(down: false), readback: "GEAR UP") }
            if any("down") { return VoiceCommand(.gear(down: true), readback: "GEAR DOWN") }
        }

        if set.contains("flaps") {
            let positions: [(word: String, position: String, spoken: String)] = [
                ("full", "FULL", "FULL"), ("3", "3", "THREE"), ("2", "2", "TWO"), ("1", "1", "ONE"),
                ("0", "0", "ZERO"), ("up", "0", "ZERO"),
            ]
            if let match = positions.first(where: { set.contains($0.word) }) {
                return VoiceCommand(.set([.init("flaps.lever", match.position)]), readback: "FLAPS \(match.spoken)")
            }
        }

        if has("landing", "light") {
            let both = { (position: String) in [VoiceCommand.Target("ext_lt.land_l", position), .init("ext_lt.land_r", position)] }
            if any("retract") { return VoiceCommand(.set(both("RETRACT")), readback: "LANDING LIGHTS RETRACTED") }
            if on { return VoiceCommand(.set(both("ON")), readback: "LANDING LIGHTS ON") }
            if off { return VoiceCommand(.set(both("OFF")), readback: "LANDING LIGHTS OFF") }
        }

        if set.contains("nose") || has("taxi", "light") {
            if any("takeoff") { return VoiceCommand(.set([.init("ext_lt.nose", "T.O")]), readback: "NOSE LIGHT TAKEOFF") }
            if off { return VoiceCommand(.set([.init("ext_lt.nose", "OFF")]), readback: "NOSE LIGHT OFF") }
            if on || any("taxi") { return VoiceCommand(.set([.init("ext_lt.nose", "TAXI")]), readback: "NOSE LIGHT TAXI") }
        }

        if set.contains("strobe") {
            if any("auto") { return VoiceCommand(.set([.init("ext_lt.strobe", "AUTO")]), readback: "STROBE AUTO") }
            if on { return VoiceCommand(.set([.init("ext_lt.strobe", "ON")]), readback: "STROBE ON") }
            if off { return VoiceCommand(.set([.init("ext_lt.strobe", "OFF")]), readback: "STROBE OFF") }
        }

        if set.contains("beacon") {
            if on { return VoiceCommand(.set([.init("ext_lt.beacon", "ON")]), readback: "BEACON ON") }
            if off { return VoiceCommand(.set([.init("ext_lt.beacon", "OFF")]), readback: "BEACON OFF") }
        }

        if set.contains("belts") {
            if on { return VoiceCommand(.set([.init("signs.seat_belts", "ON")]), readback: "SEAT BELTS ON") }
            if off { return VoiceCommand(.set([.init("signs.seat_belts", "OFF")]), readback: "SEAT BELTS OFF") }
        }

        if set.contains("spoilers") {
            if any("disarm", "retract") { return VoiceCommand(.set([.init("speedbrake.lever", "RET")]), readback: "SPOILERS DISARMED") }
            if any("arm") { return VoiceCommand(.set([.init("speedbrake.lever", "ARM")]), readback: "SPOILERS ARMED") }
        }

        if set.contains("autopilot") {
            let second = set.contains("2")
            return VoiceCommand(.fcu(second ? "fcu.ap2" : "fcu.ap1"), readback: second ? "AUTOPILOT TWO" : "AUTOPILOT ONE")
        }
        if set.contains("autothrust") {
            return VoiceCommand(.fcu("fcu.athr"), readback: "AUTOTHRUST")
        }

        if set.contains("apu") {
            if set.contains("bleed") {
                if on { return VoiceCommand(.set([.init("air_cond.apu_bleed", "ON")]), readback: "APU BLEED ON") }
                if off { return VoiceCommand(.set([.init("air_cond.apu_bleed", "OFF")]), readback: "APU BLEED OFF") }
            } else {
                if any("start") { return VoiceCommand(.apuStart, readback: "APU START") }
                if off { return VoiceCommand(.set([.init("apu.master", "OFF")]), readback: "APU OFF") }
            }
        }

        if set.contains("tcas") {
            if has("ta", "ra") { return VoiceCommand(.set([.init("tcas.mode", "TA/RA")]), readback: "TCAS TA RA") }
            if set.contains("ta") { return VoiceCommand(.set([.init("tcas.mode", "TA")]), readback: "TCAS TA ONLY") }
            if any("standby", "off") { return VoiceCommand(.set([.init("tcas.mode", "STBY")]), readback: "TCAS STANDBY") }
        }

        if set.contains("antiice") {
            let engines = [VoiceCommand.Target("anti_ice.eng1", on ? "ON" : "OFF"), .init("anti_ice.eng2", on ? "ON" : "OFF")]
            guard on || off else { return nil }
            if set.contains("wing") {
                return VoiceCommand(.set(engines + [.init("anti_ice.wing", on ? "ON" : "OFF")]),
                                    readback: on ? "ENGINE AND WING ANTI ICE ON" : "ENGINE AND WING ANTI ICE OFF")
            }
            return VoiceCommand(.set(engines), readback: on ? "ENGINE ANTI ICE ON" : "ENGINE ANTI ICE OFF")
        }

        if set.contains("ignition") {
            return VoiceCommand(.set([.init("eng.mode", off ? "NORM" : "IGN/START")]), readback: off ? "MODE NORM" : "IGNITION")
        }
        return nil
    }

    /// Lowercased, accents and punctuation removed, phrases joined and synonyms (Spanish
    /// included) mapped to one English word each.
    static func normalize(_ text: String) -> [String] {
        var line = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : " " }
            .joined()
        line = " " + line.split(separator: " ").joined(separator: " ") + " "
        let phrases: [(String, String)] = [
            (" take off ", " takeoff "), (" line up ", " lineup "), (" seat belts ", " belts "), (" seat belt ", " belts "),
            (" seatbelts ", " belts "), (" seatbelt ", " belts "), (" anti ice ", " antiice "), (" auto pilot ", " autopilot "),
            (" piloto automatico ", " autopilot "), (" auto thrust ", " autothrust "), (" auto throttle ", " autothrust "),
            (" autothrottle ", " autothrust "), (" tara ", " ta ra "), (" t a r a ", " ta ra "),
            (" stand by ", " standby "), (" a p u ", " apu "), (" check list ", " flow "),
        ]
        // Twice: adjacent phrases share their spaces (" take off " in " take off flow ").
        for _ in 0..<2 {
            for (phrase, replacement) in phrases {
                line = line.replacingOccurrences(of: phrase, with: replacement)
            }
        }
        let synonyms: [String: String] = [
            // Numbers as the recogniser writes them.
            "one": "1", "won": "1", "uno": "1", "two": "2", "dos": "2", "three": "3", "tree": "3", "tres": "3",
            "zero": "0", "cero": "0", "completo": "full", "completos": "full", "flap": "flaps",
            // On / off.
            "encender": "on", "enciende": "on", "encendidas": "on", "encendido": "on", "encendida": "on",
            "conecta": "on", "conectar": "on", "apagar": "off", "apaga": "off", "apagadas": "off", "apagado": "off",
            "apagada": "off", "desconecta": "off", "desconectar": "off",
            // Directions and actions.
            "arriba": "up", "sube": "up", "subir": "up", "abajo": "down", "baja": "down", "bajar": "down", "fuera": "down",
            "retracted": "retract", "recoger": "retract", "recoge": "retract", "recogidas": "retract", "retraer": "retract",
            "armar": "arm", "arma": "arm", "armados": "arm", "armed": "arm", "desarmar": "disarm", "desarma": "disarm",
            "disarmed": "disarm", "arrancar": "start", "arranca": "start", "starting": "start",
            // Things.
            "tren": "gear", "lights": "light", "luces": "light", "luz": "light", "aterrizaje": "landing",
            "morro": "nose", "rodaje": "taxi", "cinturones": "belts", "cinturon": "belts", "estroboscopicas": "strobe",
            "strobes": "strobe", "baliza": "beacon", "anticolision": "beacon", "despegue": "takeoff",
            "arranque": "start", "despues": "after", "antes": "before", "alineacion": "lineup", "ascenso": "climb",
            "descenso": "descent", "flujo": "flow", "procedimiento": "flow", "checks": "flow", "items": "flow",
            "spoiler": "spoilers", "sangrado": "bleed", "antihielo": "antiice", "ala": "wing", "wings": "wing",
            "motores": "engine", "engines": "engine", "ignicion": "ignition", "automatico": "auto", "espera": "standby",
            "stby": "standby",
        ]
        return line.split(separator: " ").map { synonyms[String($0)] ?? String($0) }
    }
}

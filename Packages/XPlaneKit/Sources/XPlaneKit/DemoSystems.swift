import Foundation

// Systems model of the demo: what depends on what, and what takes time. `DemoSimulator` reads
// the switch positions, steps this model on every change and twice a second, and writes back
// the results (lamps, the APU start button, ON BAT, FCU power, the MCDU screen, lighting).
//
//   power    nothing without batteries; batteries light the overhead; AC (GPU through EXT PWR,
//            APU GEN, or an engine generator) powers the FCU, the MCDU and the integral lighting
//   APU      MASTER SW opens the air intake (START is ignored until it is open), START spools
//            the APU up to AVAIL, MASTER SW OFF lets it cool down
//   ADIRS    each IR aligns in NAV (or gets attitude in ATT) over time; ON BAT while starting
//            and while only the batteries feed it
//   engines  MASTER ON starts the engine with ENG MODE at IGN/START and bleed air for its side
//            (APU BLEED, or the other engine with X BLEED open)
//
// Durations are the real ones scaled by `DemoTiming`: realistic, fast (one fifth) or instant.

public enum DemoTiming: String, Codable, CaseIterable, Sendable, Identifiable {
    case realistic
    case fast
    case instant

    public var id: String { rawValue }

    /// Multiplier on the real durations.
    public var factor: Double {
        switch self {
        case .realistic: return 1
        case .fast: return 0.2
        case .instant: return 0
        }
    }
}

/// What the demo tells the panel about the aircraft, published on `dataref` as JSON text.
public struct DemoSystemsStatus: Codable, Equatable, Sendable {
    public enum Power: Int, Codable, Sendable, Comparable {
        case none
        case battery
        case ac

        public static func < (lhs: Power, rhs: Power) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public struct Line: Codable, Equatable, Hashable, Sendable {
        public let text: String
        /// "green" done, "cyan" in progress, "amber" needs attention.
        public let color: String

        public init(_ text: String, _ color: String) {
            self.text = text
            self.color = color
        }
    }

    public let power: Power
    /// "EXT PWR", "APU GEN", "GEN 1"… while there is AC.
    public let acSource: String?
    /// ECAM-memo style lines: power, APU, IRS, engines and the latest notice.
    public let lines: [Line]

    /// Pseudo dataref the demo publishes the status on.
    public static let dataref = "demo/systems"

    public init(power: Power, acSource: String?, lines: [Line]) {
        self.power = power
        self.acSource = acSource
        self.lines = lines
    }

    public var encoded: XPValue {
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        return .string(String(decoding: data, as: UTF8.self))
    }

    public static func decode(_ value: XPValue) -> DemoSystemsStatus? {
        guard case .string(let text) = value else { return nil }
        return try? JSONDecoder().decode(DemoSystemsStatus.self, from: Data(text.utf8))
    }
}

/// Switch positions the systems read, by meaning.
struct DemoSwitches: Sendable, Equatable {
    var battery = false
    var gpu = false
    var extPower = false
    var apuMaster = false
    var apuStart = false
    var apuBleed = false
    var apuGen = true
    var generators = [true, true]
    /// "OFF", "NAV" or "ATT" per ADIRU.
    var irModes = ["OFF", "OFF", "OFF"]
    var engineMasters = [false, false]
    /// "CRANK", "NORM" or "IGN/START".
    var engineMode = "NORM"
    var engineBleeds = [true, true]
    /// "SHUT", "AUTO" or "OPEN".
    var crossBleed = "AUTO"
    var enginePumps = [true, true]
    var packs = [true, true]
    var fireHandles = [false, false]
}

struct DemoAircraft: Sendable {
    /// Real durations in seconds.
    enum Durations {
        static let apuIntake = 5.0
        static let apuStart = 50.0
        static let apuCooldown = 60.0
        static let irAlign = 600.0
        static let irAttitude = 30.0
        static let irOnBat = 5.0
        static let engineStart = 45.0
        /// How long a notice stays in the memo (not scaled).
        static let notice = 5.0
    }

    var timing: DemoTiming = .realistic

    /// APU air intake, 0 closed … 1 open.
    private(set) var apuIntake = 0.0
    /// APU start progress while it spools up.
    private(set) var apuSpool: Double?
    private(set) var apuAvailable = false
    /// Seconds of cool-down left after MASTER SW OFF.
    private(set) var apuCooldown = 0.0
    /// Alignment progress of each IR, 0 … 1.
    private(set) var irProgress = [0.0, 0.0, 0.0]
    /// Seconds since each IR was switched on.
    private(set) var irElapsed = [0.0, 0.0, 0.0]
    /// Per engine: nil stopped, 0 ..< 1 starting, 1 running.
    private(set) var engines: [Double?] = [nil, nil]
    private(set) var notice: (text: String, left: Double)?

    // MARK: Derived

    func acSource(_ s: DemoSwitches) -> String? {
        for i in 0..<2 where isRunning(i) && s.generators[i] { return "GEN \(i + 1)" }
        if s.gpu && s.extPower { return "EXT PWR" }
        if apuAvailable && s.apuGen { return "APU GEN" }
        return nil
    }

    func power(_ s: DemoSwitches) -> DemoSystemsStatus.Power {
        if acSource(s) != nil { return .ac }
        return s.battery ? .battery : .none
    }

    func isRunning(_ engine: Int) -> Bool { engines[engine] == 1 }

    /// Bleed air reaches engine `i`'s side of the duct.
    func bleed(forEngine i: Int, _ s: DemoSwitches) -> Bool {
        if apuAvailable && s.apuBleed && (i == 0 || s.crossBleed != "SHUT") { return true }
        let other = 1 - i
        return isRunning(other) && s.engineBleeds[other] && s.crossBleed == "OPEN"
    }

    /// Some bleed air in the duct, for the packs.
    func bleedAvailable(_ s: DemoSwitches) -> Bool {
        (apuAvailable && s.apuBleed) || (0..<2).contains { isRunning($0) && s.engineBleeds[$0] }
    }

    /// The APU START button stays lit only while the APU spools up.
    var apuStarterLit: Bool { apuSpool != nil }

    func onBattery(_ s: DemoSwitches) -> Bool {
        let on = s.irModes.indices.filter { s.irModes[$0] != "OFF" }
        guard !on.isEmpty, power(s) != .none else { return false }
        if power(s) == .battery { return true }
        return on.contains { irElapsed[$0] < Durations.irOnBat * timing.factor }
    }

    // MARK: Step

    /// Advances the systems by `dt` seconds with the switches as they are now. `dt` 0 applies a
    /// switch change without letting time pass (instant timing still completes processes).
    mutating func step(_ dt: Double, _ s: DemoSwitches) {
        if var current = notice {
            current.left -= dt
            notice = current.left > 0 ? current : nil
        }
        let powered = power(s) != .none
        stepAPU(dt, s, powered: powered)
        stepADIRS(dt, s, powered: power(s) != .none)
        stepEngines(dt, s, powered: power(s) != .none)
    }

    private mutating func stepAPU(_ dt: Double, _ s: DemoSwitches, powered: Bool) {
        guard s.apuMaster else {
            if apuAvailable || apuSpool != nil {
                apuCooldown = Durations.apuCooldown * timing.factor
            }
            apuAvailable = false
            apuSpool = nil
            apuCooldown = max(0, apuCooldown - dt)
            if apuCooldown == 0 { apuIntake = 0 }
            if s.apuStart { say("APU START ignorado: primero APU MASTER SW") }
            return
        }
        apuCooldown = 0
        if powered || apuAvailable {
            apuIntake = advance(apuIntake, dt, Durations.apuIntake)
        }
        if s.apuStart, apuSpool == nil, !apuAvailable {
            if !powered {
                say("APU START ignorado: sin energía")
            } else if apuIntake < 1 {
                say("APU START ignorado: la toma de aire del APU aún se está abriendo")
            } else {
                apuSpool = 0
            }
        }
        if let progress = apuSpool {
            let next = advance(progress, dt, Durations.apuStart)
            if next >= 1 {
                apuSpool = nil
                apuAvailable = true
            } else {
                apuSpool = next
            }
        }
    }

    private mutating func stepADIRS(_ dt: Double, _ s: DemoSwitches, powered: Bool) {
        for i in 0..<3 {
            switch s.irModes[i] {
            case "NAV", "ATT":
                guard powered else { continue }
                irElapsed[i] += dt
                let duration = s.irModes[i] == "NAV" ? Durations.irAlign : Durations.irAttitude
                irProgress[i] = advance(irProgress[i], dt, duration)
            default:
                irProgress[i] = 0
                irElapsed[i] = 0
            }
        }
    }

    private mutating func stepEngines(_ dt: Double, _ s: DemoSwitches, powered: Bool) {
        for i in 0..<2 {
            guard s.engineMasters[i], !s.fireHandles[i] else {
                engines[i] = nil
                continue
            }
            if let progress = engines[i] {
                if progress < 1 { engines[i] = advance(progress, dt, Durations.engineStart) }
            } else if s.engineMode == "IGN/START", powered, bleed(forEngine: i, s) {
                engines[i] = advance(0, dt, Durations.engineStart)
            }
        }
    }

    private func advance(_ progress: Double, _ dt: Double, _ duration: Double) -> Double {
        let scaled = duration * timing.factor
        return scaled <= 0 ? 1 : min(1, progress + dt / scaled)
    }

    private mutating func say(_ text: String) {
        notice = (text, Durations.notice)
    }

    // MARK: Status

    func status(_ s: DemoSwitches) -> DemoSystemsStatus {
        let power = power(s)
        let source = acSource(s)
        guard power != .none else {
            return DemoSystemsStatus(power: .none, acSource: nil, lines: [.init("AVIÓN SIN ENERGÍA: BAT 1 + 2", "amber")])
        }
        var lines: [DemoSystemsStatus.Line] = []
        if let source {
            lines.append(.init("AC: \(source)", "green"))
        } else {
            lines.append(.init("SOLO BATERÍAS", "amber"))
        }
        if s.gpu && !s.extPower { lines.append(.init("GPU CONECTADA · EXT PWR AVAIL", "cyan")) }

        if s.apuMaster {
            if apuAvailable {
                lines.append(.init(s.apuBleed ? "APU AVAIL · APU BLEED" : "APU AVAIL", "green"))
            } else if let spool = apuSpool {
                lines.append(.init("APU ARRANCANDO \(Int(spool * 100)) %", "cyan"))
            } else if apuIntake < 1 {
                lines.append(.init("APU: ABRIENDO TOMA DE AIRE", "cyan"))
            } else {
                lines.append(.init("APU LISTO PARA START", "cyan"))
            }
        } else if apuCooldown > 0 {
            lines.append(.init("APU ENFRIANDO \(Self.time(apuCooldown))", "cyan"))
        }

        let irsOn = s.irModes.indices.filter { s.irModes[$0] != "OFF" }
        if !irsOn.isEmpty {
            let remaining = irsOn.map { i -> Double in
                let duration = s.irModes[i] == "NAV" ? Durations.irAlign : Durations.irAttitude
                return (1 - irProgress[i]) * duration * timing.factor
            }.max() ?? 0
            if remaining > 0 {
                lines.append(.init("IRS EN ALINEACIÓN · \(Self.time(remaining))", "cyan"))
            } else {
                lines.append(.init(irsOn.count == 3 ? "IRS 1+2+3 ALINEADAS" : "IRS ALINEADAS: \(irsOn.count) DE 3", irsOn.count == 3 ? "green" : "amber"))
            }
        }

        for i in 0..<2 where s.engineMasters[i] {
            let name = "ENG \(i + 1)"
            if s.fireHandles[i] {
                lines.append(.init("\(name): PULSADOR DE FUEGO ACTIVADO", "amber"))
            } else if isRunning(i) {
                lines.append(.init("\(name) EN MARCHA", "green"))
            } else if let progress = engines[i] {
                lines.append(.init("\(name) ARRANCANDO \(Int(progress * 100)) %", "cyan"))
            } else if s.engineMode != "IGN/START" {
                lines.append(.init("\(name): ENG MODE NO ESTÁ EN IGN/START", "amber"))
            } else if !bleed(forEngine: i, s) {
                lines.append(.init("\(name): SIN AIRE DE ARRANQUE (APU BLEED)", "amber"))
            }
        }
        if let notice { lines.append(.init(notice.text, "amber")) }
        return DemoSystemsStatus(power: power, acSource: source, lines: lines)
    }

    /// "7 MIN", "45 S".
    static func time(_ seconds: Double) -> String {
        let rounded = Int(seconds.rounded(.up))
        return rounded >= 60 ? "\(Int((seconds / 60).rounded(.up))) MIN" : "\(rounded) S"
    }
}

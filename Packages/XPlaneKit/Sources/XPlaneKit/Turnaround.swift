import Foundation

// Turnaround: the ground time before a departure, planned backwards from the off-blocks time
// (EOBT), read from `mapping/turnaround/*.json`. Each milestone is due a number of minutes before
// off-blocks and is done when its procedures are complete, its controls read the wanted
// positions, its ground service has finished or its event (OUT) has happened; manual milestones
// (walkaround, ATC clearance) are ticked by hand. Ground services (deboarding, refuelling,
// boarding) run on a clock that can pause, and the block times (OUT, OFF, ON, IN) are detected
// from the aircraft. A slot (CTOT) gives the take-off window, and late departures carry an IATA
// delay code into the logbook, where punctuality is measured as A15.

public struct TurnaroundBook: Codable, Sendable {
    public let id: String
    public let title: String
    public let turnarounds: [TurnaroundTemplate]
}

public struct TurnaroundTemplate: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let summary: String?
    public let milestones: [TurnaroundMilestone]
    /// Suggested boarding and deboarding durations for this kind of turn, minutes.
    public let boardingMinutes: Double?
    public let deboardingMinutes: Double?

    public func uses(_ service: TurnaroundService) -> Bool {
        milestones.contains { $0.service == service }
    }
}

public enum TurnaroundService: String, Codable, Sendable, CaseIterable {
    case deboarding
    case refuel
    case boarding
}

public struct TurnaroundMilestone: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    /// Minutes relative to off-blocks: -35 is due 35 minutes before.
    public let minutes: Int
    public let note: String?
    public let why: String?
    /// Done when all of these procedures are complete.
    public let procedures: [String]?
    /// Done when this ground service has finished.
    public let service: TurnaroundService?
    /// Done when this block event happens ("out").
    public let event: String?
    /// Done when every control reads one of its expected positions (TOBOGANES ARMED).
    public var checks: [ProcedureCheck]? = nil
    /// Nothing can sense it (walkaround, ATC clearance): ticked by hand.
    public var manual: Bool? = nil

    public var isManual: Bool { manual ?? false }
}

/// What the user plans: the flight, the off-blocks time and the load.
public struct TurnaroundPlan: Codable, Sendable, Equatable {
    public var templateID: String
    public var offBlocks: Date
    public var flightNumber: String
    public var origin: String
    public var destination: String
    public var passengers: Int
    public var blockFuelKg: Double
    public var boardingMinutes: Double
    public var refuelKgPerMinute: Double
    /// Start ground services by themselves when they fall due.
    public var autoServices: Bool
    /// Calculated take-off time of an ATFM slot, if the flight has one.
    public var ctot: Date? = nil
    /// Expected taxi-out time, minutes (for the slot).
    public var taxiMinutes: Double? = nil
    /// Passengers arriving on the inbound flight (short turns), for deboarding.
    public var arrivingPassengers: Int? = nil
    public var deboardingMinutes: Double? = nil

    public var taxi: Double { taxiMinutes ?? 10 }

    public init(templateID: String, offBlocks: Date, flightNumber: String = "", origin: String = "",
                destination: String = "", passengers: Int = 150, blockFuelKg: Double = 6000,
                boardingMinutes: Double = 20, refuelKgPerMinute: Double = 600, autoServices: Bool = true) {
        self.templateID = templateID
        self.offBlocks = offBlocks
        self.flightNumber = flightNumber
        self.origin = origin
        self.destination = destination
        self.passengers = passengers
        self.blockFuelKg = blockFuelKg
        self.boardingMinutes = boardingMinutes
        self.refuelKgPerMinute = refuelKgPerMinute
        self.autoServices = autoServices
    }
}

/// A clock for a ground service that can run, pause and resume.
public struct ServiceClock: Codable, Sendable, Equatable {
    /// Seconds run before the current stretch.
    public private(set) var accumulated: Double = 0
    public private(set) var runningSince: Date?
    public private(set) var started = false

    public init() {}

    public var isRunning: Bool { runningSince != nil }

    public mutating func start(at date: Date) {
        guard runningSince == nil else { return }
        runningSince = date
        started = true
    }

    public mutating func pause(at date: Date) {
        guard let since = runningSince else { return }
        accumulated += max(0, date.timeIntervalSince(since))
        runningSince = nil
    }

    public func elapsed(at date: Date) -> Double {
        accumulated + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// 0…1 over `duration` seconds; a zero duration is complete once started.
    public func progress(at date: Date, duration: Double) -> Double {
        guard started else { return 0 }
        guard duration > 0 else { return 1 }
        return min(1, elapsed(at: date) / duration)
    }
}

public enum MilestoneState: Sendable, Equatable {
    /// More than five minutes before it is due.
    case upcoming
    /// Due now or within five minutes.
    case due
    /// Not done and past its time plus tolerance; minutes late.
    case late(Int)
    /// Done; minutes after (positive) or before (negative) its time.
    case done(Int)
}

public enum TurnaroundSchedule {
    /// Minutes a milestone may slip before it counts as late.
    public static let toleranceMinutes = 2

    public static func due(_ milestone: TurnaroundMilestone, offBlocks: Date) -> Date {
        offBlocks.addingTimeInterval(Double(milestone.minutes) * 60)
    }

    public static func state(of milestone: TurnaroundMilestone, offBlocks: Date, now: Date, doneAt: Date?) -> MilestoneState {
        let due = due(milestone, offBlocks: offBlocks)
        if let doneAt {
            return .done(Int((doneAt.timeIntervalSince(due) / 60).rounded()))
        }
        let minutes = now.timeIntervalSince(due) / 60
        if minutes < -5 { return .upcoming }
        if minutes <= Double(toleranceMinutes) { return .due }
        return .late(Int(minutes.rounded(.down)))
    }

    /// Expected delay at off-blocks in minutes: the worst lateness among milestones not done,
    /// or the delay of the latest one done when all are.
    public static func delay(_ milestones: [TurnaroundMilestone], offBlocks: Date, now: Date, doneAt: [String: Date]) -> Int {
        var worst = 0
        for milestone in milestones {
            switch state(of: milestone, offBlocks: offBlocks, now: now, doneAt: doneAt[milestone.id]) {
            case .late(let minutes): worst = max(worst, minutes)
            case .done(let minutes) where milestone.event != nil: worst = max(worst, minutes)
            default: break
            }
        }
        return worst
    }
}

/// An ATFM slot: take-off between five minutes before and ten after the CTOT. Off-blocks
/// should come a taxi time earlier.
public struct SlotWindow: Sendable, Equatable {
    public let ctot: Date
    public let taxiMinutes: Double

    public init(ctot: Date, taxiMinutes: Double) {
        self.ctot = ctot
        self.taxiMinutes = taxiMinutes
    }

    public var earliestTakeoff: Date { ctot.addingTimeInterval(-5 * 60) }
    public var latestTakeoff: Date { ctot.addingTimeInterval(10 * 60) }
    /// Off-blocks that lands the take-off on the CTOT.
    public var targetOffBlocks: Date { ctot.addingTimeInterval(-taxiMinutes * 60) }
    /// Last off-blocks that still makes the window.
    public var latestOffBlocks: Date { latestTakeoff.addingTimeInterval(-taxiMinutes * 60) }

    public enum Status: Sendable, Equatable {
        /// On course: off-blocks (done or still to come) before the latest one.
        case onTime
        /// Less than five minutes left before the latest off-blocks.
        case tight
        /// The latest off-blocks has passed without OUT: a new slot is needed.
        case missed
    }

    public func status(now: Date, outTime: Date?) -> Status {
        if let outTime { return outTime <= latestOffBlocks ? .onTime : .missed }
        if now > latestOffBlocks { return .missed }
        return latestOffBlocks.timeIntervalSince(now) < 5 * 60 ? .tight : .onTime
    }
}

/// IATA standard delay codes (AHM 730) most used on a short-haul turnaround.
public struct DelayCode: Sendable, Hashable, Identifiable {
    public let code: Int
    public let group: String
    public let text: String

    public var id: Int { code }

    public static let common: [DelayCode] = [
        DelayCode(code: 11, group: "Pasaje y equipaje", text: "Facturación tardía, aceptación fuera de plazo"),
        DelayCode(code: 12, group: "Pasaje y equipaje", text: "Facturación tardía por congestión"),
        DelayCode(code: 15, group: "Pasaje y equipaje", text: "Embarque: discrepancias, pasajero que no aparece"),
        DelayCode(code: 18, group: "Pasaje y equipaje", text: "Procesado y clasificación de equipaje"),
        DelayCode(code: 31, group: "Handling", text: "Documentación del avión tarde o errónea, hoja de carga"),
        DelayCode(code: 32, group: "Handling", text: "Carga y descarga: carga especial, falta de personal"),
        DelayCode(code: 33, group: "Handling", text: "Equipos de carga: falta o avería"),
        DelayCode(code: 34, group: "Handling", text: "Equipos de servicio: escaleras, falta o avería"),
        DelayCode(code: 35, group: "Handling", text: "Limpieza del avión"),
        DelayCode(code: 36, group: "Handling", text: "Repostaje o descarga de combustible"),
        DelayCode(code: 37, group: "Handling", text: "Catering"),
        DelayCode(code: 39, group: "Handling", text: "Equipos técnicos: GPU, aire de arranque, tractor"),
        DelayCode(code: 41, group: "Técnico", text: "Averías del avión"),
        DelayCode(code: 61, group: "Operaciones y tripulación", text: "Plan de vuelo tarde o cambiado"),
        DelayCode(code: 62, group: "Operaciones y tripulación", text: "Requisitos operativos: combustible, cambio de carga"),
        DelayCode(code: 63, group: "Operaciones y tripulación", text: "Tripulación tarde a bordo o procedimientos de salida"),
        DelayCode(code: 64, group: "Operaciones y tripulación", text: "Falta de tripulación de vuelo"),
        DelayCode(code: 71, group: "Meteorología", text: "Meteorología en el aeropuerto de salida"),
        DelayCode(code: 75, group: "Meteorología", text: "Deshielo del avión"),
        DelayCode(code: 81, group: "ATC y aeropuerto", text: "ATFM: demanda o capacidad en ruta"),
        DelayCode(code: 82, group: "ATC y aeropuerto", text: "ATFM: personal o equipos ATC en ruta"),
        DelayCode(code: 83, group: "ATC y aeropuerto", text: "ATFM: restricción en el aeropuerto de destino"),
        DelayCode(code: 84, group: "ATC y aeropuerto", text: "ATFM: meteorología en destino"),
        DelayCode(code: 87, group: "ATC y aeropuerto", text: "Instalaciones del aeropuerto: puestos, congestión en plataforma"),
        DelayCode(code: 89, group: "ATC y aeropuerto", text: "Restricciones en salida: puesta en marcha, pushback"),
        DelayCode(code: 93, group: "Reaccionario", text: "Rotación: llegada tarde del avión del vuelo anterior"),
    ]

    public static func named(_ code: Int?) -> DelayCode? {
        code.flatMap { code in common.first { $0.code == code } }
    }
}

/// Loadsheet figures from the plan, with standard masses. Indicative: the real one comes from the
/// airline's load control.
public struct LoadSheet: Sendable, Equatable {
    /// Typical A320 dry operating weight, kg.
    public static let dryOperatingWeight = 42_500.0
    /// Standard adult with hand luggage, kg.
    public static let passengerMass = 84.0
    /// Average checked bag per passenger, kg.
    public static let bagMass = 13.0
    public static let taxiFuel = 200.0
    public static let maxZeroFuelWeight = 62_500.0
    public static let maxTakeoffWeight = 78_000.0

    public let passengers: Int
    public let zeroFuelWeight: Double
    public let blockFuel: Double
    public let takeoffWeight: Double

    public init(passengers: Int, blockFuel: Double) {
        self.passengers = passengers
        self.blockFuel = blockFuel
        zeroFuelWeight = Self.dryOperatingWeight + Double(passengers) * (Self.passengerMass + Self.bagMass)
        takeoffWeight = zeroFuelWeight + blockFuel - Self.taxiFuel
    }

    public var withinLimits: Bool {
        zeroFuelWeight <= Self.maxZeroFuelWeight && takeoffWeight <= Self.maxTakeoffWeight
    }
}

/// OUT, OFF, ON and IN times of one flight.
public struct BlockTimes: Codable, Sendable, Equatable {
    public var outTime: Date?
    public var offTime: Date?
    public var onTime: Date?
    public var inTime: Date?

    public init(outTime: Date? = nil, offTime: Date? = nil, onTime: Date? = nil, inTime: Date? = nil) {
        self.outTime = outTime
        self.offTime = offTime
        self.onTime = onTime
        self.inTime = inTime
    }

    /// OUT to IN, minutes.
    public var blockMinutes: Int? {
        guard let outTime, let inTime else { return nil }
        return Int((inTime.timeIntervalSince(outTime) / 60).rounded())
    }

    /// OFF to ON, minutes.
    public var flightMinutes: Int? {
        guard let offTime, let onTime else { return nil }
        return Int((onTime.timeIntervalSince(offTime) / 60).rounded())
    }
}

/// Detects the block events from the aircraft: OUT when the parking brake is released, OFF and
/// ON when the wheels leave and touch the ground, IN when the parking brake is set after landing.
public struct BlockTimeDetector: Sendable, Equatable {
    public private(set) var times = BlockTimes()
    private var parkBrake: Bool?
    private var onGround: Bool?

    public init(times: BlockTimes = BlockTimes()) {
        self.times = times
    }

    /// Feeds the current readings (nil while unknown). Returns true when an event was stamped.
    @discardableResult
    public mutating func update(at date: Date, parkBrake brake: Bool?, onGround ground: Bool?) -> Bool {
        let before = times
        if let brake, let previous = parkBrake, brake != previous {
            if !brake, times.outTime == nil { times.outTime = date }
            if brake, times.onTime != nil, times.inTime == nil { times.inTime = date }
        }
        if let ground, let previous = onGround, ground != previous {
            if !ground, times.outTime != nil, times.offTime == nil { times.offTime = date }
            if ground, times.offTime != nil, times.onTime == nil { times.onTime = date }
        }
        if brake != nil { parkBrake = brake }
        if ground != nil { onGround = ground }
        return times != before
    }

    /// Stamps an event by hand ("out", "off", "on", "in").
    public mutating func stamp(_ event: String, at date: Date) {
        switch event {
        case "out": times.outTime = date
        case "off": times.offTime = date
        case "on": times.onTime = date
        case "in": times.inTime = date
        default: break
        }
    }
}

/// A finished flight in the logbook.
public struct FlightLogEntry: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var flightNumber: String
    public var origin: String
    public var destination: String
    public var offBlocksPlanned: Date
    public var times: BlockTimes
    public var passengers: Int
    /// IATA delay code when the flight left late.
    public var delayCode: Int? = nil
    public var delayNote: String? = nil
    public var ctot: Date? = nil

    public init(id: UUID = UUID(), flightNumber: String, origin: String, destination: String,
                offBlocksPlanned: Date, times: BlockTimes, passengers: Int) {
        self.id = id
        self.flightNumber = flightNumber
        self.origin = origin
        self.destination = destination
        self.offBlocksPlanned = offBlocksPlanned
        self.times = times
        self.passengers = passengers
    }

    /// Minutes between the planned and the actual off-blocks time.
    public var departureDelay: Int? {
        times.outTime.map { Int(($0.timeIntervalSince(offBlocksPlanned) / 60).rounded()) }
    }

    /// A15: left no more than 15 minutes after the planned off-blocks time.
    public var isOnTimeA15: Bool? {
        departureDelay.map { $0 <= 15 }
    }

    /// Share of flights with an OUT time that left within 15 minutes (0…1); nil without any.
    public static func a15(_ entries: [FlightLogEntry]) -> Double? {
        let judged = entries.compactMap(\.isOnTimeA15)
        guard !judged.isEmpty else { return nil }
        return Double(judged.filter { $0 }.count) / Double(judged.count)
    }
}

public enum TurnaroundLoader {
    /// Every `*.json` in `directory`, books in file-name order.
    public static func loadAll(in directory: URL) throws -> [TurnaroundTemplate] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return try files
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { try JSONDecoder().decode(TurnaroundBook.self, from: Data(contentsOf: $0)).turnarounds }
    }
}

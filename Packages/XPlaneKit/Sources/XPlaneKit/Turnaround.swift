import Foundation

// Turnaround: the ground time before a departure, planned backwards from the off-blocks time
// (EOBT), read from `mapping/turnaround/*.json`. Each milestone is due a number of minutes before
// off-blocks and is done when its procedures are complete, its ground service has finished or
// its event (OUT) has happened. Ground services (boarding, refuelling) run on a clock that can
// pause, and the block times (OUT, OFF, ON, IN) are detected from the aircraft.

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
}

public enum TurnaroundService: String, Codable, Sendable, CaseIterable {
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

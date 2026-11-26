import Foundation

// The aircraft the pilot is flying. The A320 is the base: its mapping lives in `mapping/` and every
// figure below matches what the app used before profiles existed. Other aircraft add an overlay
// folder (`mapping/aircraft/<id>/`) whose files replace the base files at the same relative path
// (e.g. `overhead/fuel.json`) and add new ones; whatever the overlay does not touch (FCU, EFIS,
// RMP, MCDU…) is shared, since ToLiss uses the same cockpit and datarefs across its Airbus family.

public struct AircraftProfile: Sendable, Hashable, Identifiable {
    /// Stable id, stored on the device: "a320", "a340".
    public let id: String
    /// Short name for titles: "A320".
    public let name: String
    /// What the pilot loads in X-Plane: "ToLiss A320".
    public let product: String
    /// ICAO type designator used in flight plans and ATC ("A320", "A346").
    public let icaoType: String
    /// ICAO types X-Plane may report for an aircraft flown with this profile (`acf_ICAO`).
    public let detectedTypes: [String]
    /// Overlay folder under `mapping/`, nil for the base aircraft.
    public let mappingOverlay: String?
    public let engineCount: Int
    /// Usual engine start order on the ground, engine numbers.
    public let startSequence: [Int]
    /// Seats offered in a typical two-class layout (turnaround planner limit).
    public let maxPassengers: Int
    /// Typical dry operating weight, kg.
    public let dryOperatingWeight: Double
    public let maxZeroFuelWeight: Double
    public let maxTakeoffWeight: Double
    public let maxLandingWeight: Double
    /// Fuel planned for taxi, kg.
    public let taxiFuel: Double
    /// Idle burn on the ground, kg per minute per engine.
    public let idleBurnPerEngine: Double
    /// Pitch at which the tail touches the runway with the main gear compressed, degrees.
    public let tailStrikePitch: Double
    /// Cabin doors on the left side, for the walk-around and the ground services.
    public let passengerDoors: Int
    /// Engines left off on a reduced-engine taxi out and started before take-off: engine 2 on the
    /// A320, the outboard engines 1 and 4 on the A340 (taxi on the inboard pair).
    public let lateStartEngines: [Int]

    public init(id: String, name: String, product: String, icaoType: String, detectedTypes: [String],
                mappingOverlay: String?, engineCount: Int, startSequence: [Int], maxPassengers: Int,
                dryOperatingWeight: Double, maxZeroFuelWeight: Double, maxTakeoffWeight: Double,
                maxLandingWeight: Double, taxiFuel: Double, idleBurnPerEngine: Double,
                tailStrikePitch: Double, passengerDoors: Int, lateStartEngines: [Int]) {
        self.id = id
        self.name = name
        self.product = product
        self.icaoType = icaoType
        self.detectedTypes = detectedTypes
        self.mappingOverlay = mappingOverlay
        self.engineCount = engineCount
        self.startSequence = startSequence
        self.maxPassengers = maxPassengers
        self.dryOperatingWeight = dryOperatingWeight
        self.maxZeroFuelWeight = maxZeroFuelWeight
        self.maxTakeoffWeight = maxTakeoffWeight
        self.maxLandingWeight = maxLandingWeight
        self.taxiFuel = taxiFuel
        self.idleBurnPerEngine = idleBurnPerEngine
        self.tailStrikePitch = tailStrikePitch
        self.passengerDoors = passengerDoors
        self.lateStartEngines = lateStartEngines
    }

    /// ToLiss A319/A320/A321: the figures the app always used (A320ceo).
    public static let a320 = AircraftProfile(
        id: "a320", name: "A320", product: "ToLiss A320", icaoType: "A320",
        detectedTypes: ["A318", "A319", "A320", "A321", "A19N", "A20N", "A21N"],
        mappingOverlay: nil, engineCount: 2, startSequence: [2, 1], maxPassengers: 180,
        dryOperatingWeight: 42_500, maxZeroFuelWeight: 62_500, maxTakeoffWeight: 78_000,
        maxLandingWeight: 66_000, taxiFuel: 200, idleBurnPerEngine: 5,
        tailStrikePitch: 11.7, passengerDoors: 2, lateStartEngines: [2])

    /// ToLiss A340-600 (Trent 556): FCOM/ACAP figures, rounded. Two-class layout of about 380 seats;
    /// the -600 is long, so its tail touches much earlier than the A320's.
    public static let a340 = AircraftProfile(
        id: "a340", name: "A340", product: "ToLiss A340-600", icaoType: "A346",
        detectedTypes: ["A342", "A343", "A345", "A346"],
        mappingOverlay: "aircraft/a340", engineCount: 4, startSequence: [4, 3, 2, 1], maxPassengers: 380,
        dryOperatingWeight: 177_000, maxZeroFuelWeight: 245_000, maxTakeoffWeight: 368_000,
        maxLandingWeight: 259_000, taxiFuel: 600, idleBurnPerEngine: 7,
        tailStrikePitch: 9.5, passengerDoors: 4, lateStartEngines: [1, 4])

    public static let all: [AircraftProfile] = [.a320, .a340]

    /// Profile by stored id; the A320 for anything unknown.
    public static func named(_ id: String?) -> AircraftProfile {
        all.first { $0.id == id } ?? .a320
    }

    /// Profile matching the ICAO type X-Plane reports, nil when none does.
    public static func detected(icao: String?) -> AircraftProfile? {
        guard let code = icao?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).uppercased(),
              !code.isEmpty else { return nil }
        return all.first { $0.detectedTypes.contains(code) }
    }

    /// "ENG 1"…"ENG 4".
    public var engineNumbers: [Int] { Array(1...engineCount) }

    /// Engines started before take-off on a reduced-engine taxi, as words: "2", "1 y 4".
    public var lateStartEnginesText: String {
        lateStartEngines.map(String.init).joined(separator: " y ")
    }

    /// Loadsheet basis with this aircraft's standard figures.
    public var loadSheetBasis: LoadSheet.Basis {
        if self == .a320 { return .standard }
        return LoadSheet.Basis(dryOperatingWeight: dryOperatingWeight,
                               massPerPassenger: LoadSheet.passengerMass + LoadSheet.bagMass,
                               taxiFuel: taxiFuel, maxZeroFuelWeight: maxZeroFuelWeight,
                               maxTakeoffWeight: maxTakeoffWeight, maxLandingWeight: nil, tripFuel: nil, fromOFP: false)
    }
}

// MARK: Mapping overlay

public enum MappingOverlay {
    /// Folder of the base mapping that holds the aircraft overlays; never loaded as part of the base.
    public static let folder = "aircraft"

    /// Builds in `destination` the mapping of an aircraft: every file of `base` (except the
    /// overlays folder) with the files of `overlay` laid on top at the same relative path.
    /// An overlay file named `<name>.removed` deletes `<name>` from the result.
    /// `destination` is emptied first. Returns `destination`.
    @discardableResult
    public static func merge(base: URL, overlay: URL, into destination: URL) throws -> URL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        try copyTree(from: base, to: destination, skippingTopLevel: [folder])
        try copyTree(from: overlay, to: destination, skippingTopLevel: [])
        return destination
    }

    /// Relative paths of the regular files under `root`, sorted.
    public static func relativeFiles(in root: URL, skippingTopLevel skipped: Set<String> = []) -> [String] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var paths: [String] = []
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                if enumerator.level == 1, skipped.contains(url.lastPathComponent) { enumerator.skipDescendants() }
                continue
            }
            let components = Array(url.pathComponents.suffix(enumerator.level))
            paths.append(components.joined(separator: "/"))
        }
        return paths.sorted()
    }

    private static func copyTree(from source: URL, to destination: URL, skippingTopLevel skipped: Set<String>) throws {
        let fileManager = FileManager.default
        for path in relativeFiles(in: source, skippingTopLevel: skipped) {
            let target = destination.appendingPathComponent(path)
            if path.hasSuffix(".removed") {
                let removed = destination.appendingPathComponent(String(path.dropLast(".removed".count)))
                if fileManager.fileExists(atPath: removed.path) { try fileManager.removeItem(at: removed) }
                continue
            }
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
            try fileManager.copyItem(at: source.appendingPathComponent(path), to: target)
        }
    }
}

// MARK: Ground figures per aircraft

extension Taxi {
    /// Fuel saved taxiing out with the late-start engines off for `minutes`, kg. On the A320 it is
    /// `singleEngineSaving` (one engine at 5 kg/min); on the A340, the two outboard engines.
    public static func reducedEngineSaving(minutes: Double, aircraft: AircraftProfile) -> Double {
        max(0, minutes - warmUpMinutes - 2) * aircraft.idleBurnPerEngine * Double(aircraft.lateStartEngines.count)
    }
}

extension AircraftProfile {
    /// Boarding time the turnaround planner offers, minutes.
    public var boardingMinutesRange: ClosedRange<Double> { engineCount > 2 ? 10...70 : 5...40 }
    /// Deboarding time the turnaround planner offers, minutes.
    public var deboardingMinutesRange: ClosedRange<Double> { engineCount > 2 ? 5...40 : 3...20 }
    /// Starting load of a new turnaround plan (A320: the planner's usual 150 and 6 000 kg).
    public var defaultPassengers: Int { engineCount > 2 ? 300 : 150 }
    public var defaultBlockFuel: Double { engineCount > 2 ? 80_000 : 6000 }
    public var defaultRefuelRate: Double { engineCount > 2 ? 1500 : 600 }
    /// Block fuel the planner offers, kg, and its step.
    public var blockFuelRange: ClosedRange<Double> { engineCount > 2 ? 10_000...155_000 : 1000...18_000 }
    public var blockFuelStep: Double { engineCount > 2 ? 500 : 100 }
    /// Refuelling rate the planner offers, kg per minute.
    public var refuelRateRange: ClosedRange<Double> { engineCount > 2 ? 500...3000 : 200...2000 }
    /// Ground burn with every engine at idle, kg per minute (A320 about 10-12, A340 about 25-30).
    public var allEnginesTaxiBurn: ClosedRange<Int> {
        let low = Int((idleBurnPerEngine * Double(engineCount)).rounded())
        return low...(low + engineCount)
    }
}

extension WalkaroundPoint {
    /// The exterior inspection of `aircraft`: the A320 route, or the A340's with four engines and
    /// the centre main gear of the -600.
    public static func route(for aircraft: AircraftProfile) -> [WalkaroundPoint] {
        guard aircraft.engineCount > 2 else { return route }
        var points: [WalkaroundPoint] = []
        for point in route {
            switch point.id {
            case "left_engine":
                points.append(WalkaroundPoint(id: "engine_2", area: "Motor 2", checks: "Toma de aire y álabes del fan, capós cerrados y asegurados, reversa guardada, sin fugas"))
                points.append(WalkaroundPoint(id: "left_engine", area: "Motor 1", checks: "Toma y fan, capós, reversa, sin fugas; pilón y drenajes"))
            case "left_main_gear":
                points.append(point)
                points.append(WalkaroundPoint(id: "center_gear", area: "Tren central", checks: "Neumáticos, frenos, amortiguador, sin fugas, pasador retirado"))
            case "right_engine":
                points.append(WalkaroundPoint(id: "right_engine", area: "Motor 4", checks: "Toma y fan, capós, reversa, sin fugas; pilón y drenajes"))
                points.append(WalkaroundPoint(id: "engine_3", area: "Motor 3", checks: "Toma y fan, capós, reversa, sin fugas"))
            default:
                points.append(point)
            }
        }
        return points
    }
}

import Foundation

// Data-driven description of cockpit panels. The JSON files live in `mapping/` at the
// repository root and are bundled with the app as a folder reference, so ToLiss changes are
// a data edit, not a code change.
//
//   mapping/layout.json          groups (overhead, pedestal…) and flight phases
//   mapping/<group>/<panel>.json one subpanel each

public struct SubpanelDefinition: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    /// Panel group this subpanel belongs to, e.g. "overhead". Defaults to "overhead".
    public let group: String?
    public let order: Int?
    public let columns: Int?
    public let controls: [ControlDefinition]
    public let notes: String?

    public var groupID: String { group ?? "overhead" }
}

public struct ControlDefinition: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case toggle2   // two-position lever switch
        case toggle3   // three-position lever switch
        case korry     // square pushbutton with up to two annunciator legends
        case rotary    // rotary selector with N detents
    }

    public let id: String
    public let label: String
    public let kind: Kind
    /// Position names ordered bottom → top (levers) or left → right (rotaries).
    public let positions: [String]
    /// Where the current position is read from.
    public let state: ValueBinding?
    /// Where to write when the user moves the control. Defaults to `state`.
    public let write: ValueBinding?
    /// Optional commands; when present they take precedence over `write`.
    /// Levers: `up`/`down`. Korry: `press`, or `up` (=on) / `down` (=off) chosen from the current state.
    public let commands: CommandBinding?
    public let lamps: Lamps?
    /// Korry only: a cover must be lifted before the button accepts a press.
    public let guarded: Bool?
    /// Shows state but refuses input. Used while a candidate mapping is being verified.
    public let readOnly: Bool?
    public let col: Int
    public let row: Int
    public let verified: Bool?
    public let notes: String?

    public var isVerified: Bool { verified ?? false }
    public var isReadOnly: Bool { readOnly ?? false }
    public var writeBinding: ValueBinding? { write ?? state }
}

public struct ValueBinding: Codable, Sendable {
    public let dataref: String
    public let index: Int?
    /// Raw dataref value for each position. Defaults to 0, 1, 2, …
    public let values: [Double]?
    /// Extra raw values that map to a position, keyed by the raw value as text,
    /// e.g. `{"2": 0}` when 2 means "available but off".
    public let aliases: [String: Int]?

    public var key: DatarefKey { DatarefKey(dataref, index: index) }

    func table(count: Int) -> [Double] {
        values ?? (0..<count).map { Double($0) }
    }

    /// Position for a raw value: alias first, then nearest table entry. Nil when not numeric.
    public func position(for value: XPValue, count: Int) -> Int? {
        guard let raw = value.doubleValue else { return nil }
        if let aliases, raw.rounded() == raw, let aliased = aliases[String(Int(raw))] {
            return aliased
        }
        var best: (index: Int, distance: Double)?
        for (index, candidate) in table(count: count).enumerated() {
            let distance = abs(candidate - raw)
            if best == nil || distance < best!.distance {
                best = (index, distance)
            }
        }
        return best?.index
    }

    public func value(for position: Int, count: Int) -> Double {
        let entries = table(count: count)
        return entries.indices.contains(position) ? entries[position] : Double(position)
    }
}

public struct CommandBinding: Codable, Sendable {
    public let up: String?
    public let down: String?
    public let press: String?
    /// Seconds to hold the command (X-Plane max 10). Default 0 = press and release.
    public let duration: Double?
}

public struct Lamps: Codable, Sendable {
    public let top: Lamp?
    public let bottom: Lamp?
}

public struct Lamp: Codable, Sendable {
    public let text: String
    /// "amber", "green", "white" or "blue".
    public let color: String
    public let dataref: String?
    public let index: Int?
    /// Lit when the value equals this. Default: value > 0.5.
    public let onValue: Double?
    /// Lit when `(value & bit) != 0`. Takes precedence over `onValue`.
    public let bit: Int?
    /// Inverts the result (lamp lit when the condition is false), e.g. an OFF legend.
    public let invert: Bool?

    public var key: DatarefKey? {
        dataref.map { DatarefKey($0, index: index) }
    }

    public func isLit(_ value: XPValue?) -> Bool {
        guard let raw = value?.doubleValue else { return false }
        let lit: Bool
        if let bit {
            lit = (Int(raw.rounded()) & bit) != 0
        } else if let onValue {
            lit = abs(onValue - raw) < 0.01
        } else {
            lit = raw > 0.5
        }
        return invert == true ? !lit : lit
    }
}

// MARK: Layout (groups and phases)

public struct PanelGroup: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let icon: String?
}

public struct FlightPhase: Codable, Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let icon: String?
    /// Subpanel ids to show, from any group, in this order.
    public let subpanels: [String]
}

public struct PanelLayout: Codable, Sendable {
    public let groups: [PanelGroup]
    public let phases: [FlightPhase]

    public static let empty = PanelLayout(groups: [], phases: [])

    public init(groups: [PanelGroup], phases: [FlightPhase]) {
        self.groups = groups
        self.phases = phases
    }
}

public enum PanelLoader {
    public static func load(from url: URL) throws -> SubpanelDefinition {
        try JSONDecoder().decode(SubpanelDefinition.self, from: Data(contentsOf: url))
    }

    /// Loads every subpanel `*.json` under `directory` (recursively, skipping `layout.json`,
    /// the `reference` folder and files without a `controls` array, such as the FCU),
    /// sorted by `order` then title.
    public static func loadAll(in directory: URL) throws -> [SubpanelDefinition] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var panels: [SubpanelDefinition] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
            if url.lastPathComponent == "layout.json" { continue }
            if url.pathComponents.contains("reference") { continue }
            let data = try Data(contentsOf: url)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["controls"] != nil else { continue }
            panels.append(try JSONDecoder().decode(SubpanelDefinition.self, from: data))
        }
        return panels.sorted {
            let lhs = $0.order ?? Int.max
            let rhs = $1.order ?? Int.max
            return lhs == rhs ? $0.title < $1.title : lhs < rhs
        }
    }

    public static func loadLayout(in directory: URL) throws -> PanelLayout {
        let url = directory.appendingPathComponent("layout.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return .empty }
        return try JSONDecoder().decode(PanelLayout.self, from: Data(contentsOf: url))
    }
}

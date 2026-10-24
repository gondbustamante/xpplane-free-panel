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
    /// Position and size on the group's canvas, in canvas units. When present the subpanel is
    /// drawn at true geometry and its controls use `x`/`y`; otherwise it falls back to a grid.
    public let frame: PanelFrame?
    /// Where the title is drawn, relative to the frame. Default: top centre.
    public let titleAt: [Double]?
    public let titleHidden: Bool?
    /// Static artwork: synoptic lines, arrows, boxed labels, dividers.
    public let decorations: [Decoration]?
    public let controls: [ControlDefinition]
    public let notes: String?

    public var groupID: String { group ?? "overhead" }
    public var isAbsolute: Bool { frame != nil }
}

/// Rectangle in canvas units (origin top-left).
public struct PanelFrame: Codable, Sendable {
    public let x: Double
    public let y: Double
    public let w: Double
    public let h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

/// Static artwork inside a subpanel. Coordinates are in canvas units relative to the subpanel.
///   line     points[]                 polyline (green by default)
///   arrow    at, direction            small filled triangle
///   bracket  points[2]                line with short end ticks (e.g. "L TK PUMPS")
///   box      at, text                 white-outlined label box ("GREEN", "AC BUS 1")
///   text     at, text, size, vertical plain label
///   divider  points[2]                thin white separator line
public struct Decoration: Codable, Sendable {
    public let type: String
    public let points: [[Double]]?
    public let at: [Double]?
    public let text: String?
    public let color: String?
    public let width: Double?
    public let size: Double?
    public let direction: String?
    public let vertical: Bool?
}

public struct ValueRange: Codable, Sendable {
    public let min: Double
    public let max: Double

    public func clamp(_ value: Double) -> Double { Swift.min(Swift.max(value, min), max) }
    public func fraction(of value: Double) -> Double {
        guard max > min else { return 0 }
        return (clamp(value) - min) / (max - min)
    }
    public func value(at fraction: Double) -> Double {
        min + (max - min) * Swift.min(Swift.max(fraction, 0), 1)
    }
}

public struct ControlDefinition: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case toggle2   // two-position lever switch
        case toggle3   // three-position lever switch
        case korry     // square pushbutton with up to two annunciator legends
        case rotary    // rotary selector with N detents
        case knob      // continuous knob over `range` (temperature, brightness, LDG ELEV)
        case display   // read-out: number with `format`, or text when `format` is "text"
        case lever     // long-travel lever with N detents (flaps, speed brake)
        case dualKnob  // concentric knob: outer ring `up`/`down`, inner `upSmall`/`downSmall` (RMP)
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
    /// "red" (solid hinged cover) or "cage" (black see-through frame). Default "cage".
    public let guardStyle: String?
    /// Visual variant: korry "round" (round black pushbutton) or "fire" (red fire handle).
    public let style: String?
    /// Small vertical legend beside a korry ("AUTO").
    public let sideLabel: String?
    /// Draws the label under the body instead of above (ADIRS "ADIR 1" under its selector).
    public let labelBelow: Bool?
    /// Knob: value range. Display: unused.
    public let range: ValueRange?
    /// Display: printf-style format, e.g. "%.1fV"; "text" for strings; "baro" for a BARO window.
    public let format: String?
    /// BARO window (`format` "baro"): `state` holds inHg; these flags pick STD and the hPa unit.
    public let baro: BaroBinding?
    /// Shows state but refuses input. Used while a candidate mapping is being verified.
    public let readOnly: Bool?
    /// Grid placement (subpanels without `frame`).
    public let col: Int?
    public let row: Int?
    /// Centre of the control body in canvas units relative to the subpanel (subpanels with `frame`).
    public let x: Double?
    public let y: Double?
    /// Body size override in canvas units (korry side, toggle bezel, knob diameter).
    public let size: Double?
    public let verified: Bool?
    public let notes: String?

    public var isVerified: Bool { verified ?? false }
    public var isReadOnly: Bool { readOnly ?? false }
    public var writeBinding: ValueBinding? { write ?? state }
    public var gridColumn: Int { col ?? 0 }
    public var gridRow: Int { row ?? 0 }
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
    /// Knob pulled (BARO: QNH). `press` is the push (BARO: STD).
    public let pull: String?
    /// Dual knob: inner (small step) knob.
    public let upSmall: String?
    public let downSmall: String?
    /// Seconds to hold the command (X-Plane max 10). Default 0 = press and release.
    public let duration: Double?
}

/// Flags of a BARO reference window.
public struct BaroBinding: Codable, Sendable {
    /// Non-zero when the knob is pushed to STD.
    public let std: String
    /// Non-zero when the unit is hPa, zero for inHg.
    public let unit: String

    /// Window text: "Std", "1013" (hPa) or "29.92" (inHg); nil while values are missing.
    public static func text(inHg: Double?, std: Double?, hectopascal: Double?) -> String? {
        if let std, std > 0.5 { return "Std" }
        guard let inHg, inHg > 0 else { return nil }
        if let hectopascal, hectopascal > 0.5 {
            return String(Int((inHg * hectopascalsPerInHg).rounded()))
        }
        return String(format: "%.2f", inHg)
    }

    public static let hectopascalsPerInHg = 33.8639
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

/// Physical arrangement of a group's subpanels: columns (left → right), each a list of rows
/// (top → bottom), each a list of subpanel ids drawn side by side.
public struct PanelArrangement: Codable, Sendable {
    public let notes: String?
    public let columns: [[[String]]]

    public init(notes: String? = nil, columns: [[[String]]]) {
        self.notes = notes
        self.columns = columns
    }

    public var placedIDs: Set<String> {
        Set(columns.flatMap { $0.flatMap { $0 } })
    }
}

/// Size of a group's canvas in canvas units, for subpanels placed with `frame`.
public struct CanvasSize: Codable, Sendable {
    public let width: Double
    public let height: Double
}

public struct PanelLayout: Codable, Sendable {
    public let groups: [PanelGroup]
    public let phases: [FlightPhase]
    /// Optional arrangement per group id. Groups without one flow left to right and wrap.
    public let arrangements: [String: PanelArrangement]?
    /// Optional canvas per group id. Subpanels of that group with a `frame` are drawn at
    /// their true position on it.
    public let canvases: [String: CanvasSize]?

    public static let empty = PanelLayout(groups: [], phases: [], arrangements: nil, canvases: nil)

    public init(groups: [PanelGroup], phases: [FlightPhase], arrangements: [String: PanelArrangement]? = nil,
                canvases: [String: CanvasSize]? = nil) {
        self.groups = groups
        self.phases = phases
        self.arrangements = arrangements
        self.canvases = canvases
    }

    public func arrangement(for group: String) -> PanelArrangement? {
        arrangements?[group]
    }

    public func canvas(for group: String) -> CanvasSize? {
        canvases?[group]
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

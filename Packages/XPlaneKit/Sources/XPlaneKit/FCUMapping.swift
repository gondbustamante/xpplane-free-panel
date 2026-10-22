import Foundation

// Data-driven description of the Flight Control Unit (the autopilot panel on the glareshield).
// Unlike the overhead, the FCU is one fixed panel: four selectors (SPD/MACH, HDG/TRK, ALT,
// V/S-FPA), each with a numeric window and a knob that turns, pushes and pulls, plus a set of
// pushbuttons. What *is* data is where each value, flag and command lives in ToLiss, so the JSON
// (`mapping/fcu/fcu.json`) can be corrected without touching code.

public struct FCUDefinition: Codable, Sendable {
    public let id: String
    public let title: String
    public let notes: String?
    /// When present and zero, the FCU is unpowered and the windows go dark.
    public let available: FCUBinding?
    public let selectors: [FCUSelectorDefinition]
    public let buttons: [FCUButtonDefinition]

    /// Every dataref the panel reads, for one batch subscription.
    public var datarefNames: Set<String> {
        var names = Set<String>()
        if let available { names.insert(available.dataref) }
        for selector in selectors {
            names.insert(selector.value.dataref)
            for binding in [selector.alternateValue, selector.mode, selector.managed, selector.dashed, selector.write] {
                if let binding { names.insert(binding.dataref) }
            }
        }
        for button in buttons {
            if let lit = button.lit { names.insert(lit.dataref) }
            if let state = button.state { names.insert(state.dataref) }
        }
        return names
    }

    public func buttons(in column: String) -> [FCUButtonDefinition] {
        buttons.filter { $0.column == column }
    }
}

/// A dataref (optionally one element of an array) read as a number or as a flag.
public struct FCUBinding: Codable, Sendable {
    public let dataref: String
    public let index: Int?
    /// For flags: the value that counts as "on". Defaults to "greater than 0.5".
    public let onValue: Double?

    public init(dataref: String, index: Int? = nil, onValue: Double? = nil) {
        self.dataref = dataref
        self.index = index
        self.onValue = onValue
    }

    public var key: DatarefKey { DatarefKey(dataref, index: index) }

    public func isOn(_ value: XPValue?) -> Bool {
        guard let raw = value?.doubleValue else { return false }
        if let onValue { return abs(onValue - raw) < 0.01 }
        return raw > 0.5
    }
}

public struct FCURange: Codable, Sendable {
    public let min: Double
    public let max: Double

    public init(min: Double, max: Double) {
        self.min = min
        self.max = max
    }

    public func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(value, min), max)
    }
}

/// How a window renders its value, and how typed input is parsed back.
public enum FCUFormat: String, Codable, Sendable {
    case speed            // 250
    case mach             // .78
    case heading          // 005
    case altitude         // 05000
    case verticalSpeed    // +25oo  (hundreds of ft/min, as on the real unit)
    case flightPathAngle  // +2.5

    /// What the window shows when the value is dashed or unknown.
    public var dashes: String {
        switch self {
        case .speed, .heading: return "---"
        case .mach: return "-.--"
        case .altitude: return "-----"
        case .verticalSpeed: return "-----"
        case .flightPathAngle: return "-.-"
        }
    }

    /// Increment used when the mapping has no rotate command and the value is written directly.
    public var defaultStep: Double {
        switch self {
        case .speed, .heading: return 1
        case .mach: return 0.01
        case .altitude, .verticalSpeed: return 100
        case .flightPathAngle: return 0.1
        }
    }

    public var isAngle: Bool { self == .heading }

    public func text(for value: Double?) -> String {
        guard let value, value.isFinite else { return dashes }
        switch self {
        case .speed:
            return String(format: "%03d", Int(value.rounded()))
        case .mach:
            let text = String(format: "%.2f", value)
            return text.hasPrefix("0") ? String(text.dropFirst()) : text
        case .heading:
            var degrees = Int(value.rounded()) % 360
            if degrees < 0 { degrees += 360 }
            return String(format: "%03d", degrees)
        case .altitude:
            return String(format: "%05d", max(Int(value.rounded()), 0))
        case .verticalSpeed:
            let hundreds = Int((abs(value) / 100).rounded())
            return (value < 0 ? "-" : "+") + String(format: "%02d", hundreds) + "oo"
        case .flightPathAngle:
            return (value < 0 ? "-" : "+") + String(format: "%.1f", abs(value))
        }
    }

    /// Parses what the user typed. Accepts "0.78" and ".78" for Mach and "," as decimal separator.
    public func parse(_ text: String) -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        if cleaned.hasPrefix("+") { cleaned.removeFirst() }
        if cleaned.hasPrefix(".") { cleaned = "0" + cleaned }
        if cleaned.hasPrefix("-.") { cleaned = "-0" + String(cleaned.dropFirst()) }
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }
}

public struct FCUSelectorCommands: Codable, Sendable {
    public let increase: String?
    public let decrease: String?
    /// Knob pushed in: managed mode (the dot).
    public let push: String?
    /// Knob pulled out: selected mode.
    public let pull: String?

    public init(increase: String? = nil, decrease: String? = nil, push: String? = nil, pull: String? = nil) {
        self.increase = increase
        self.decrease = decrease
        self.push = push
        self.pull = pull
    }
}

public struct FCUSelectorDefinition: Codable, Identifiable, Sendable {
    public let id: String
    /// Legend above the window, e.g. "SPD".
    public let label: String
    /// Legend when `mode` is on, e.g. "MACH".
    public let alternateLabel: String?
    public let format: FCUFormat
    public let alternateFormat: FCUFormat?
    /// Value shown in the window and, unless `write` says otherwise, written on direct entry.
    public let value: FCUBinding
    /// Optional separate dataref read while `mode` is on (e.g. FPA instead of V/S).
    public let alternateValue: FCUBinding?
    /// Flag that switches to the alternate label/format/value.
    public let mode: FCUBinding?
    /// Flag for the managed dot next to the digits.
    public let managed: FCUBinding?
    /// Flag that blanks the digits to dashes.
    public let dashed: FCUBinding?
    public let write: FCUBinding?
    public let range: FCURange?
    public let alternateRange: FCURange?
    public let commands: FCUSelectorCommands?
    public let verified: Bool?
    public let notes: String?

    public var isVerified: Bool { verified ?? false }
    public var writeBinding: FCUBinding { write ?? value }

    public func activeFormat(modeOn: Bool) -> FCUFormat {
        modeOn ? (alternateFormat ?? format) : format
    }

    public func activeLabel(modeOn: Bool) -> String {
        modeOn ? (alternateLabel ?? label) : label
    }

    public func activeValueBinding(modeOn: Bool) -> FCUBinding {
        modeOn ? (alternateValue ?? value) : value
    }

    public func activeRange(modeOn: Bool) -> FCURange? {
        modeOn ? (alternateRange ?? range) : range
    }
}

public struct FCUButtonDefinition: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Fires `command`; lights when `lit` is on.
        case push
        /// Cycles `state` through `values` by writing it (e.g. the ALT 100/1000 selector).
        case toggle
    }

    public let id: String
    public let label: String
    /// Second line of the legend, e.g. "TRK FPA" under "HDG V/S".
    public let sublabel: String?
    /// Which column the button is drawn in: a selector id, or "center" for the AP block.
    public let column: String
    public let kind: Kind?
    public let command: String?
    public let lit: FCUBinding?
    public let state: FCUBinding?
    /// Toggle only: legend for each value, in the same order as `values`.
    public let positions: [String]?
    /// Toggle only: raw value for each position. Defaults to 0, 1, 2, …
    public let values: [Double]?
    public let verified: Bool?
    public let notes: String?

    public var isVerified: Bool { verified ?? false }
    public var resolvedKind: Kind { kind ?? .push }

    func table() -> [Double] {
        values ?? (0..<(positions?.count ?? 2)).map { Double($0) }
    }

    /// Toggle only: index of the position nearest to the raw value.
    public func position(for value: XPValue?) -> Int? {
        guard let raw = value?.doubleValue else { return nil }
        var best: (index: Int, distance: Double)?
        for (index, candidate) in table().enumerated() {
            let distance = abs(candidate - raw)
            if best == nil || distance < best!.distance { best = (index, distance) }
        }
        return best?.index
    }

    /// Toggle only: raw value to write after the position currently shown.
    public func nextValue(after current: XPValue?) -> Double {
        let entries = table()
        guard !entries.isEmpty else { return 0 }
        let index = position(for: current) ?? 0
        return entries[(index + 1) % entries.count]
    }
}

public enum FCULoader {
    public static func load(from url: URL) throws -> FCUDefinition {
        try JSONDecoder().decode(FCUDefinition.self, from: Data(contentsOf: url))
    }

    /// Loads the first `*.json` found directly inside `directory`, or nil when there is none.
    public static func loadFirst(in directory: URL) throws -> FCUDefinition? {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard let first = files.first else { return nil }
        return try load(from: first)
    }
}

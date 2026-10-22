import Foundation

// Data-driven description of a cockpit subpanel. The JSON files live in `mapping/` at the
// repository root and are bundled with the app as a folder reference, so ToLiss changes are
// a data edit, not a code change.

public struct SubpanelDefinition: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let order: Int?
    public let columns: Int?
    public let controls: [ControlDefinition]
    public let notes: String?
}

public struct ControlDefinition: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case toggle2   // two-position lever switch
        case toggle3   // three-position lever switch
        case korry     // square pushbutton with up to two annunciator legends
    }

    public let id: String
    public let label: String
    public let kind: Kind
    /// Position names ordered bottom → top (index 0 is the lowest lever position).
    public let positions: [String]
    /// Where the current position is read from.
    public let state: ValueBinding?
    /// Where to write when the user moves the control. Defaults to `state`.
    public let write: ValueBinding?
    /// Optional commands; when present they take precedence over `write`.
    public let commands: CommandBinding?
    public let lamps: Lamps?
    public let col: Int
    public let row: Int
    public let verified: Bool?
    public let notes: String?

    public var isVerified: Bool { verified ?? false }
    public var writeBinding: ValueBinding? { write ?? state }
}

public struct ValueBinding: Codable, Sendable {
    public let dataref: String
    public let index: Int?
    /// Raw dataref value for each position. Defaults to 0, 1, 2, …
    public let values: [Double]?

    public var key: DatarefKey { DatarefKey(dataref, index: index) }

    func table(count: Int) -> [Double] {
        values ?? (0..<count).map { Double($0) }
    }

    /// Nearest position for a raw value, or nil when the value is not numeric.
    public func position(for value: XPValue, count: Int) -> Int? {
        guard let raw = value.doubleValue else { return nil }
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
    /// Value that lights the lamp. Defaults to "greater than 0.5".
    public let onValue: Double?

    public var key: DatarefKey? {
        dataref.map { DatarefKey($0, index: index) }
    }

    public func isLit(_ value: XPValue?) -> Bool {
        guard let raw = value?.doubleValue else { return false }
        if let onValue { return abs(onValue - raw) < 0.01 }
        return raw > 0.5
    }
}

public enum PanelLoader {
    public static func load(from url: URL) throws -> SubpanelDefinition {
        try JSONDecoder().decode(SubpanelDefinition.self, from: Data(contentsOf: url))
    }

    /// Loads every `*.json` under `directory` (recursively), sorted by `order` then title.
    public static func loadAll(in directory: URL) throws -> [SubpanelDefinition] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else { return [] }
        var panels: [SubpanelDefinition] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
            panels.append(try load(from: url))
        }
        return panels.sorted {
            let lhs = $0.order ?? Int.max
            let rhs = $1.order ?? Int.max
            return lhs == rhs ? $0.title < $1.title : lhs < rhs
        }
    }
}

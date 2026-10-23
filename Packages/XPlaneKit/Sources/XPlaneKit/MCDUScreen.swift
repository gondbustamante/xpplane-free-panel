import Foundation

// Decoder for the ToLiss MCDU screen.
//
// ToLiss publishes each MCDU as 150 `data` datarefs (24 bytes each, one per colour):
//
//   AirbusFBW/MCDU<n>title{b,g,s,w,y}         row 0, large
//   AirbusFBW/MCDU<n>stitle{b,g,w,y}          row 0, small
//   AirbusFBW/MCDU<n>label<1-6>{a,b,g,m,s,w,y} rows 1,3,…,11, small
//   AirbusFBW/MCDU<n>label<1-6>{Lg,Lw}        same rows, large
//   AirbusFBW/MCDU<n>cont<1-6>{a,b,g,m,s,w,y}  rows 2,4,…,12, large
//   AirbusFBW/MCDU<n>scont<1-6>{…}            same rows, small
//   AirbusFBW/MCDU<n>spw / spa                row 13 (scratchpad), white / amber
//   AirbusFBW/MCDU<n>VertSlewKeys             1 = ↑↓, 2 = ↑, 3 = ↓
//
// Colour letters: a amber, b cyan, g green, m magenta, w white, y yellow, s special symbols.
// In the "s" strings ToLiss encodes glyphs as letters/digits (A = "[", B = "]", 0/1 = cyan ←/→,
// 2/3 = white ←/→, 4/5 = amber ←/→, E = amber box). In every string "#" is a box and "`" a
// degree sign. Mapping confirmed against the dataref dump in mapping/reference and the
// XSchenFly WinWing MCDU driver, which renders the same datarefs on hardware.

public enum MCDUColor: String, Sendable, Equatable {
    case white, cyan, green, magenta, amber, yellow
}

public struct MCDUCell: Equatable, Sendable {
    public var character: Character
    public var color: MCDUColor
    public var small: Bool

    public init(character: Character, color: MCDUColor, small: Bool) {
        self.character = character
        self.color = color
        self.small = small
    }

    public static let blank = MCDUCell(character: " ", color: .white, small: false)
    public var isBlank: Bool { character == " " }
}

public struct MCDUScreen: Equatable, Sendable {
    public static let columns = 24
    public static let rows = 14

    /// `rows` × `columns` cells, row 0 is the title, row 13 the scratchpad.
    public var cells: [[MCDUCell]]
    public var canSlewUp: Bool
    public var canSlewDown: Bool

    public static let empty = MCDUScreen(
        cells: Array(repeating: Array(repeating: .blank, count: columns), count: rows),
        canSlewUp: false, canSlewDown: false)

    public var isBlank: Bool {
        cells.allSatisfy { $0.allSatisfy(\.isBlank) }
    }

    /// Plain text of one row, for tests and debugging.
    public func text(row: Int) -> String {
        String(cells[row].map(\.character))
    }

    // MARK: Dataref names

    static let titleColors = ["b", "g", "s", "w", "y"]
    static let smallTitleColors = ["b", "g", "w", "y"]
    static let lineColors = ["a", "b", "g", "m", "s", "w", "y"]
    static let largeLabelColors = ["Lg", "Lw"]

    public static func prefix(unit: Int) -> String {
        "AirbusFBW/MCDU\(unit)"
    }

    /// All 150 datarefs that make up the screen of MCDU `unit` (1 captain, 2 first officer).
    public static func datarefNames(unit: Int) -> [String] {
        let p = prefix(unit: unit)
        var names: [String] = []
        names += titleColors.map { "\(p)title\($0)" }
        names += smallTitleColors.map { "\(p)stitle\($0)" }
        for line in 1...6 {
            names += (lineColors + largeLabelColors).map { "\(p)label\(line)\($0)" }
            names += lineColors.map { "\(p)cont\(line)\($0)" }
            names += lineColors.map { "\(p)scont\(line)\($0)" }
        }
        names += ["\(p)spw", "\(p)spa", "\(p)VertSlewKeys"]
        return names
    }

    // MARK: Decoding

    public static func decode(unit: Int, values: [String: XPValue]) -> MCDUScreen {
        var screen = MCDUScreen.empty
        let p = prefix(unit: unit)

        func place(_ suffix: String, row: Int, small: Bool, colorCode: String) {
            guard let value = values[p + suffix], let bytes = bytes(of: value) else { return }
            for (column, byte) in bytes.prefix(columns).enumerated() where byte != 0 && byte != 0x20 {
                let (character, color) = glyph(byte, colorCode: colorCode)
                screen.cells[row][column] = MCDUCell(character: character, color: color, small: small)
            }
        }

        for code in smallTitleColors { place("stitle\(code)", row: 0, small: true, colorCode: code) }
        for code in titleColors { place("title\(code)", row: 0, small: false, colorCode: code) }
        for line in 1...6 {
            for code in lineColors { place("label\(line)\(code)", row: line * 2 - 1, small: true, colorCode: code) }
            for code in largeLabelColors { place("label\(line)\(code)", row: line * 2 - 1, small: false, colorCode: code) }
            for code in lineColors { place("scont\(line)\(code)", row: line * 2, small: true, colorCode: code) }
            for code in lineColors { place("cont\(line)\(code)", row: line * 2, small: false, colorCode: code) }
        }

        // Scratchpad: white text, amber where ToLiss puts a message. Data after the first NUL is
        // stale, so stop there.
        for (suffix, code) in [("spw", "w"), ("spa", "a")] {
            guard let value = values[p + suffix], let bytes = bytes(of: value) else { continue }
            for (column, byte) in bytes.prefix(columns - 2).enumerated() {
                if byte == 0 { break }
                if byte == 0x20 { continue }
                let (character, color) = glyph(byte, colorCode: code)
                screen.cells[13][column] = MCDUCell(character: character, color: color, small: false)
            }
        }

        switch values[p + "VertSlewKeys"]?.intValue ?? 0 {
        case 1: screen.canSlewUp = true; screen.canSlewDown = true
        case 2: screen.canSlewUp = true
        case 3: screen.canSlewDown = true
        default: break
        }
        if screen.canSlewUp { screen.cells[13][columns - 2] = MCDUCell(character: "↑", color: .white, small: false) }
        if screen.canSlewDown { screen.cells[13][columns - 1] = MCDUCell(character: "↓", color: .white, small: false) }
        return screen
    }

    /// Bytes of a `data` dataref. The Web API sends them base64-encoded; plain strings and byte
    /// arrays are accepted too.
    static func bytes(of value: XPValue) -> [UInt8]? {
        switch value {
        case .string(let text):
            if !text.isEmpty, let data = Data(base64Encoded: text) {
                return [UInt8](data)
            }
            return Array(text.utf8)
        case .array(let elements):
            return elements.compactMap { $0.intValue }.map { UInt8(clamping: $0) }
        default:
            return nil
        }
    }

    static func glyph(_ byte: UInt8, colorCode: String) -> (Character, MCDUColor) {
        let character = Character(UnicodeScalar(byte))
        if colorCode == "s" {
            switch character {
            case "A": return ("[", .cyan)
            case "B": return ("]", .cyan)
            case "0": return ("←", .cyan)
            case "1": return ("→", .cyan)
            case "2": return ("←", .white)
            case "3": return ("→", .white)
            case "4": return ("←", .amber)
            case "5": return ("→", .amber)
            case "E": return ("☐", .amber)
            default: return (character, .white)
            }
        }
        let color: MCDUColor
        switch colorCode.last ?? "w" {
        case "a": color = .amber
        case "b": color = .cyan
        case "g": color = .green
        case "m": color = .magenta
        case "y": color = .yellow
        default: color = .white
        }
        switch character {
        case "#": return ("☐", color)
        case "`": return ("°", color)
        default: return (character, color)
        }
    }
}

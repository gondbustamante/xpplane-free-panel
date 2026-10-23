import SwiftUI
import XPlaneKit

/// The A320 MCDU: screen mirrored from ToLiss (`MCDUScreen`) and the full keyboard, laid out
/// after the A32NX reference photo (FlyByWire docs, `mcdu-overview.png`). Every key fires the
/// matching `AirbusFBW/MCDU<n>…` command. A hardware keyboard types into the scratchpad.
struct MCDUView: View {
    @Environment(PanelModel.self) private var model
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 10) {
            unitPicker
            MCDUBody()
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onAppear { focused = true }
                .onKeyPress(phases: .down) { press in
                    handle(press) ? .handled : .ignored
                }
        }
    }

    private var unitPicker: some View {
        @Bindable var model = model
        return HStack(spacing: 16) {
            Picker("MCDU", selection: Binding(get: { model.mcduUnit }, set: { model.setMCDUUnit($0) })) {
                Text("MCDU 1 · CAPT").tag(1)
                Text("MCDU 2 · F/O").tag(2)
            }
            .pickerStyle(.segmented)
            .frame(width: 300)
            if model.isLandscape {
                Toggle("Teclado al lado", isOn: $model.mcduWideInLandscape)
                    .toggleStyle(.button)
                    .controlSize(.small)
            }
        }
    }

    /// Hardware keyboard → MCDU keys.
    private func handle(_ press: KeyPress) -> Bool {
        switch press.key {
        case .delete, .deleteForward: model.pressMCDU("KeyClear"); return true
        case .upArrow: model.pressMCDU("SlewUp"); return true
        case .downArrow: model.pressMCDU("SlewDown"); return true
        case .leftArrow: model.pressMCDU("SlewLeft"); return true
        case .rightArrow: model.pressMCDU("SlewRight"); return true
        default: break
        }
        guard let character = press.characters.uppercased().first else { return false }
        switch character {
        case "A"..."Z", "0"..."9": model.pressMCDU("Key\(character)")
        case " ": model.pressMCDU("KeySpace")
        case "/": model.pressMCDU("KeySlash")
        case ".", ",": model.pressMCDU("KeyDecimal")
        case "-", "+": model.pressMCDU("KeyPM")
        default: return false
        }
        return true
    }
}

// MARK: - Body

private enum MCDUMetrics {
    // The real screen is 24 × 14 characters, a little taller than wide per cell.
    static let cellWidth: CGFloat = 19
    static let rowHeight: CGFloat = 28
    static let screenPadding: CGFloat = 12
    static var screenWidth: CGFloat { cellWidth * CGFloat(MCDUScreen.columns) + screenPadding * 2 }
    static var screenHeight: CGFloat { rowHeight * CGFloat(MCDUScreen.rows) + screenPadding * 2 }
    static let lskSize = CGSize(width: 40, height: 24)
    static let bezel = Color(red: 0.36, green: 0.41, blue: 0.48)
    static let bezelHighlight = Color(red: 0.43, green: 0.48, blue: 0.55)
}

/// Geometry of the official unit, taken from the A32NX reference photo (FlyByWire docs,
/// `pedestal/mcdu.jpg`, 563 × 880 px). Everything is placed at its photo position, scaled so the
/// screen is exactly the 24 × 14 character grid; the keyboard therefore keeps Airbus proportions.
private enum MCDUGeometry {
    static let width: CGFloat = 563
    static let height: CGFloat = 880
    /// Horizontal cut between the screen part and the keyboard part (for the wide layout).
    static let split: CGFloat = 425
    static let screen = CGRect(x: 97, y: 88, width: 371, height: 322)
    static var scale: CGFloat { MCDUMetrics.screenWidth / screen.width }
    static func pt(_ value: CGFloat) -> CGFloat { value * scale }
}

private extension View {
    /// Centre this view at photo coordinates, inside a part whose top is at photo y `top`.
    func at(_ x: CGFloat, _ y: CGFloat, top: CGFloat = 0) -> some View {
        position(x: MCDUGeometry.pt(x), y: MCDUGeometry.pt(y - top))
    }
}

private struct MCDUBody: View {
    @Environment(PanelModel.self) private var model

    /// Landscape with "Teclado al lado": screen part and keyboard part side by side, each in its
    /// own bezel, so the screen can be much larger. Otherwise the unit as installed.
    private var wide: Bool { model.isLandscape && model.mcduWideInLandscape }

    var body: some View {
        if wide {
            HStack(alignment: .center, spacing: 18) {
                Bezel { screenPart }
                Bezel { keyboardPart }
            }
        } else {
            Bezel {
                VStack(spacing: 0) {
                    screenPart
                    keyboardPart
                }
            }
        }
    }

    // MARK: Screen part: annunciators, screen, line select keys

    private var screenPart: some View {
        let g = MCDUGeometry.self
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(Self.screenScrews.enumerated()), id: \.offset) { _, point in
                ScrewView(size: g.pt(17)).at(point.x, point.y)
            }
            // Two white brightness knobs and the five annunciator windows between them.
            whiteKnob.at(38, 24)
            whiteKnob.at(525, 24)
            ForEach(0..<5, id: \.self) { index in
                Capsule()
                    .fill(Color(white: 0.07))
                    .overlay(Capsule().stroke(Color.black.opacity(0.7), lineWidth: 1))
                    .frame(width: g.pt(50), height: g.pt(16))
                    .at(162 + CGFloat(index) * 62, 24)
            }
            MCDUScreenView(screen: model.mcduScreen, connected: model.status == .connected)
                .at(g.screen.midX, g.screen.midY)
            LSKConnectors()
                .frame(width: g.pt(g.width), height: g.pt(g.split))
            ForEach(1...6, id: \.self) { line in
                lsk("L", line).position(x: g.pt(32), y: g.pt(g.screen.minY) + lineCenter(line))
                lsk("R", line).position(x: g.pt(531), y: g.pt(g.screen.minY) + lineCenter(line))
            }
        }
        .frame(width: g.pt(g.width), height: g.pt(g.split))
    }

    private var whiteKnob: some View {
        Circle()
            .fill(RadialGradient(colors: [Color(white: 0.98), Color(white: 0.72)],
                                 center: UnitPoint(x: 0.4, y: 0.35), startRadius: 1,
                                 endRadius: MCDUGeometry.pt(17)))
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
            .frame(width: MCDUGeometry.pt(30), height: MCDUGeometry.pt(30))
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1.5)
    }

    /// Centre of data line `n` (1…6) from the top of the screen: the LSK sits beside it.
    private func lineCenter(_ line: Int) -> CGFloat {
        MCDUMetrics.screenPadding + (CGFloat(line * 2) + 0.5) * MCDUMetrics.rowHeight
    }

    private func lsk(_ side: String, _ line: Int) -> some View {
        MCDUKey(style: .lsk, width: MCDUGeometry.pt(36), height: MCDUGeometry.pt(23)) {
            Capsule().fill(Color.white.opacity(0.9)).frame(width: MCDUGeometry.pt(18), height: 2.5).backlit()
        } action: {
            model.pressMCDU("LSK\(line)\(side)")
        }
    }

    // MARK: Keyboard part

    private var keyboardPart: some View {
        let g = MCDUGeometry.self
        let top = g.split
        return ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(Self.keyboardScrews.enumerated()), id: \.offset) { _, point in
                ScrewView(size: g.pt(17)).at(point.x, point.y, top: top)
            }
            // Recessed frames around the function keys and around AIRPORT / slew keys.
            recess(width: 400, height: 98).at(259, 481, top: top)
            recess(width: 134, height: 132).at(126, 598, top: top)

            ForEach(Array(Self.functionKeys.enumerated()), id: \.offset) { index, key in
                functionKey(key.title, key.command)
                    .at(Self.functionX[index % 6], Self.functionY[index / 6], top: top)
            }
            brtDim.at(486, 481, top: top)

            functionKey("AIR\nPORT", "Airport").at(97, 551, top: top)
            blankKey.at(161, 551, top: top)
            slewKey("arrow.left", "SlewLeft").at(97, 595, top: top)
            slewKey("arrow.up", "SlewUp").at(161, 595, top: top)
            slewKey("arrow.right", "SlewRight").at(97, 639, top: top)
            slewKey("arrow.down", "SlewDown").at(161, 639, top: top)

            sideSlot.at(28, 738, top: top)
            sideSlot.at(535, 738, top: top)

            ForEach(Array(Self.numericKeys.enumerated()), id: \.offset) { index, key in
                numericKey(key.title, key.command)
                    .at(Self.numericX[index % 3], Self.numericY[index / 3], top: top)
            }
            ForEach(Array(Self.alphaKeys.enumerated()), id: \.offset) { index, key in
                alphaKey(key.title, key.command, tactile: Self.tactileKeys.contains(key.title))
                    .at(Self.alphaX[index % 5], Self.alphaY[index / 5], top: top)
            }
        }
        .frame(width: g.pt(g.width), height: g.pt(g.height - g.split))
    }

    // Photo coordinates (px) of the key centres.
    private static let screenScrews: [CGPoint] = [CGPoint(x: 22, y: 64), CGPoint(x: 541, y: 64),
                                                  CGPoint(x: 22, y: 412), CGPoint(x: 541, y: 412)]
    private static let keyboardScrews: [CGPoint] = [CGPoint(x: 22, y: 470), CGPoint(x: 541, y: 470),
                                                    CGPoint(x: 22, y: 858), CGPoint(x: 541, y: 858)]
    private static let functionX: [CGFloat] = [97, 161.6, 226.2, 290.8, 355.4, 420]
    private static let functionY: [CGFloat] = [460, 505]
    private static let numericX: [CGFloat] = [94, 149, 203]
    private static let numericY: [CGFloat] = [700, 748, 796, 843]
    private static let alphaX: [CGFloat] = [258, 312, 366, 421, 475]
    private static let alphaY: [CGFloat] = [573, 624, 677, 731, 786, 840]
    private static let tactileKeys: Set<String> = ["E", "N", "S", "W"]

    private static let functionKeys: [MCDUKeyDef] = [
        MCDUKeyDef("DIR", "DirTo"), MCDUKeyDef("PROG", "Prog"), MCDUKeyDef("PERF", "Perf"),
        MCDUKeyDef("INIT", "Init"), MCDUKeyDef("DATA", "Data"), MCDUKeyDef("", "blank"),
        MCDUKeyDef("F-PLN", "Fpln"), MCDUKeyDef("RAD\nNAV", "RadNav"), MCDUKeyDef("FUEL\nPRED", "FuelPred"),
        MCDUKeyDef("SEC\nF-PLN", "SecFpln"), MCDUKeyDef("ATC\nCOMM", "ATC"), MCDUKeyDef("MCDU\nMENU", "Menu"),
    ]

    private static let numericKeys: [MCDUKeyDef] = [
        MCDUKeyDef("1", "Key1"), MCDUKeyDef("2", "Key2"), MCDUKeyDef("3", "Key3"),
        MCDUKeyDef("4", "Key4"), MCDUKeyDef("5", "Key5"), MCDUKeyDef("6", "Key6"),
        MCDUKeyDef("7", "Key7"), MCDUKeyDef("8", "Key8"), MCDUKeyDef("9", "Key9"),
        MCDUKeyDef(".", "KeyDecimal"), MCDUKeyDef("0", "Key0"), MCDUKeyDef("+/-", "KeyPM"),
    ]

    private static let alphaKeys: [MCDUKeyDef] =
        "ABCDEFGHIJKLMNOPQRSTUVWXY".map { MCDUKeyDef(String($0), "Key\($0)") }
        + [MCDUKeyDef("Z", "KeyZ"), MCDUKeyDef("/", "KeySlash"), MCDUKeyDef("SP", "KeySpace"),
           MCDUKeyDef("OVFY", "KeyOverfly"), MCDUKeyDef("CLR", "KeyClear")]

    private func recess(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: MCDUGeometry.pt(7))
            .fill(Color.black.opacity(0.20))
            .overlay(RoundedRectangle(cornerRadius: MCDUGeometry.pt(7))
                .stroke(LinearGradient(colors: [Color.black.opacity(0.5), Color.white.opacity(0.18)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 1.5))
            .frame(width: MCDUGeometry.pt(width), height: MCDUGeometry.pt(height))
    }

    private func functionKey(_ title: String, _ command: String) -> some View {
        Group {
            if command == "blank" {
                blankKey
            } else {
                MCDUKey(style: .function, width: MCDUGeometry.pt(58), height: MCDUGeometry.pt(33)) {
                    KeyLegend(text: title, size: MCDUGeometry.pt(title.contains("\n") ? 10.5 : 13))
                } action: {
                    model.pressMCDU(command)
                }
            }
        }
    }

    private var blankKey: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(LinearGradient(colors: [Color(white: 0.17), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.8), lineWidth: 1))
            .frame(width: MCDUGeometry.pt(58), height: MCDUGeometry.pt(33))
    }

    /// BRT and DIM share one tall black key, split in two halves.
    private var brtDim: some View {
        VStack(spacing: 0) {
            MCDUKey(style: .black, width: MCDUGeometry.pt(40), height: MCDUGeometry.pt(40)) {
                KeyLegend(text: "BRT", size: MCDUGeometry.pt(12))
            } action: { model.pressMCDU("KeyBright") }
            Rectangle().fill(Color.black).frame(width: MCDUGeometry.pt(40), height: 1)
            MCDUKey(style: .black, width: MCDUGeometry.pt(40), height: MCDUGeometry.pt(40)) {
                KeyLegend(text: "DIM", size: MCDUGeometry.pt(12))
            } action: { model.pressMCDU("KeyDim") }
        }
    }

    private func slewKey(_ symbol: String, _ command: String) -> some View {
        MCDUKey(style: .function, width: MCDUGeometry.pt(58), height: MCDUGeometry.pt(34)) {
            KeyLegend(systemImage: symbol, size: MCDUGeometry.pt(17))
        } action: {
            model.pressMCDU(command)
        }
    }

    private func numericKey(_ title: String, _ command: String) -> some View {
        MCDUKey(style: .round, width: MCDUGeometry.pt(36), height: MCDUGeometry.pt(36)) {
            KeyLegend(text: title, size: MCDUGeometry.pt(title.count > 1 ? 12 : 17))
        } action: {
            model.pressMCDU(command)
        }
    }

    private func alphaKey(_ title: String, _ command: String, tactile: Bool) -> some View {
        MCDUKey(style: .alpha, width: MCDUGeometry.pt(42), height: MCDUGeometry.pt(40)) {
            if title == "OVFY" {
                VStack(spacing: 0) {
                    KeyLegend(text: "OVFY", size: MCDUGeometry.pt(9))
                    KeyLegend(systemImage: "triangle", size: MCDUGeometry.pt(12))
                }
            } else {
                KeyLegend(text: title, size: MCDUGeometry.pt(title.count > 1 ? 14 : 19))
            }
        } action: {
            model.pressMCDU(command)
        }
        .overlay {
            // E, N, S and W carry a raised frame on the real keyboard to find them by touch.
            if tactile {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color(red: 0.86, green: 0.66, blue: 0.40).opacity(0.75), lineWidth: 1.2)
                    .padding(MCDUGeometry.pt(3))
                    .allowsHitTesting(false)
            }
        }
    }

    /// Dark vertical annunciator slot beside the keyboard.
    private var sideSlot: some View {
        Capsule()
            .fill(Color(white: 0.07))
            .overlay(Capsule().stroke(Color.black.opacity(0.7), lineWidth: 1))
            .frame(width: MCDUGeometry.pt(16), height: MCDUGeometry.pt(150))
    }
}

/// Blue-grey Airbus bezel behind a part of the MCDU.
private struct Bezel<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [MCDUMetrics.bezelHighlight, MCDUMetrics.bezel],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.6), lineWidth: 2))
                    .shadow(color: .black.opacity(0.6), radius: 14, y: 8)
            )
    }
}

/// The short white lines from each LSK to the screen edge, slightly slanted as on the unit.
private struct LSKConnectors: View {
    var body: some View {
        Canvas { context, _ in
            let g = MCDUGeometry.self
            for line in 1...6 {
                let y = g.pt(g.screen.minY) + MCDUMetrics.screenPadding + (CGFloat(line * 2) + 0.5) * MCDUMetrics.rowHeight
                var path = Path()
                path.move(to: CGPoint(x: g.pt(54), y: y - 3))
                path.addLine(to: CGPoint(x: g.pt(95), y: y + 3))
                path.move(to: CGPoint(x: g.pt(470), y: y + 3))
                path.addLine(to: CGPoint(x: g.pt(509), y: y - 3))
                context.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 1.4)
            }
        }
        .backlit()
        .allowsHitTesting(false)
    }
}

/// White key caption lit by the MCDU's integral lighting.
private struct KeyLegend: View {
    var text: String = ""
    var systemImage: String? = nil
    let size: CGFloat
    @Environment(\.backlight) private var level

    var body: some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: size, weight: .bold))
            } else {
                Text(text)
                    .font(.system(size: size, weight: .bold))
                    .fontWidth(text.contains("\n") ? .condensed : .standard)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-2)
            }
        }
        .foregroundStyle(PanelTheme.legend(level))
        .backlit()
    }
}

// MARK: - Screen

/// 24 × 14 character screen. Large and small characters share the same cell grid, as on the
/// real display, so columns stay aligned whatever the font size.
struct MCDUScreenView: View {
    let screen: MCDUScreen
    let connected: Bool

    var body: some View {
        ZStack {
            // Recessed display: dark glass with a thin inner bevel, like the real unit.
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(red: 0.015, green: 0.02, blue: 0.03))
            RoundedRectangle(cornerRadius: 7)
                .stroke(LinearGradient(colors: [Color.black, Color(white: 0.28)],
                                       startPoint: .top, endPoint: .bottom), lineWidth: 4)
            VStack(spacing: 0) {
                ForEach(0..<MCDUScreen.rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<MCDUScreen.columns, id: \.self) { column in
                            cell(screen.cells[row][column])
                        }
                    }
                }
            }
            .padding(MCDUMetrics.screenPadding)
            // One soft glow for the whole text layer (cheap) gives the emissive look of the LCD.
            .compositingGroup()
            .shadow(color: .white.opacity(0.18), radius: 1.2)
            if !connected && screen.isBlank {
                Text("SIN CONEXIÓN")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(white: 0.35))
            }
        }
        .frame(width: MCDUMetrics.screenWidth, height: MCDUMetrics.screenHeight)
    }

    /// Each character sits in a fixed cell, so a proportional sans-serif (closer to the MCDU's
    /// stroke font than a slab monospace) still lines up in columns. Small characters share
    /// the baseline of large ones, as on the aircraft.
    private func cell(_ cell: MCDUCell) -> some View {
        Text(String(cell.character))
            .font(.system(size: cell.small ? 18 : 24, weight: cell.small ? .medium : .semibold))
            .foregroundStyle(color(cell.color))
            .frame(width: MCDUMetrics.cellWidth, height: MCDUMetrics.rowHeight,
                   alignment: cell.small ? .bottom : .center)
            .offset(y: cell.small ? -1 : 0)   // offset does not change the cell's size
    }

    private func color(_ color: MCDUColor) -> Color {
        switch color {
        case .white: return Color(white: 0.97)
        case .cyan: return Color(red: 0.25, green: 0.92, blue: 1.00)
        case .green: return Color(red: 0.30, green: 1.00, blue: 0.40)
        case .magenta: return Color(red: 1.00, green: 0.40, blue: 1.00)
        case .amber: return Color(red: 1.00, green: 0.62, blue: 0.12)
        case .yellow: return Color(red: 1.00, green: 0.96, blue: 0.25)
        }
    }
}

// MARK: - Key

private struct MCDUKeyDef: Identifiable {
    let title: String
    let command: String
    var id: String { command }

    init(_ title: String, _ command: String) {
        self.title = title
        self.command = command
    }
}

/// MCDU key cap. Each style follows the unit: dark function keys, grey square letter keys,
/// black round number keys, the black BRT/DIM key and the line select keys.
private struct MCDUKey<Label: View>: View {
    enum Style { case function, alpha, round, black, lsk }

    let style: Style
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let label: () -> Label
    let action: () -> Void

    private var colors: [Color] {
        switch style {
        case .function: return [Color(white: 0.25), Color(white: 0.12)]
        case .alpha: return [Color(white: 0.30), Color(white: 0.17)]
        case .round, .black: return [Color(white: 0.16), Color(white: 0.04)]
        case .lsk: return [Color(white: 0.22), Color(white: 0.08)]
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if style == .round {
                    Circle().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    Circle().stroke(Color.black.opacity(0.85), lineWidth: 1)
                    Circle().trim(from: 0.55, to: 0.95).stroke(Color.white.opacity(0.12), lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.85), lineWidth: 1)
                    // Top bevel highlight.
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.14), .clear],
                                                     startPoint: .top, endPoint: .center), lineWidth: 1)
                }
                label()
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(KorryPressStyle())
    }
}

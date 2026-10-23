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
        Picker("MCDU", selection: Binding(get: { model.mcduUnit }, set: { model.setMCDUUnit($0) })) {
            Text("MCDU 1 · CAPT").tag(1)
            Text("MCDU 2 · F/O").tag(2)
        }
        .pickerStyle(.segmented)
        .frame(width: 300)
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
    static let cellWidth: CGFloat = 16
    static let rowHeight: CGFloat = 23
    static let screenPadding: CGFloat = 10
    static var screenWidth: CGFloat { cellWidth * CGFloat(MCDUScreen.columns) + screenPadding * 2 }
    static var screenHeight: CGFloat { rowHeight * CGFloat(MCDUScreen.rows) + screenPadding * 2 }
    static let lskSize = CGSize(width: 36, height: 21)
    static let bezel = Color(red: 0.36, green: 0.41, blue: 0.48)
    static let bezelHighlight = Color(red: 0.43, green: 0.48, blue: 0.55)
}

private struct MCDUBody: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        VStack(spacing: 14) {
            topAnnunciators
            screenRow
            pageKeys
            lowerKeyboard
        }
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [MCDUMetrics.bezelHighlight, MCDUMetrics.bezel],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.55), lineWidth: 2))
                .shadow(color: .black.opacity(0.6), radius: 14, y: 8)
        )
        .overlay(alignment: .topLeading) { ScrewView(size: 12).padding(10) }
        .overlay(alignment: .topTrailing) { ScrewView(size: 12).padding(10) }
        .overlay(alignment: .bottomLeading) { ScrewView(size: 12).padding(10) }
        .overlay(alignment: .bottomTrailing) { ScrewView(size: 12).padding(10) }
    }

    /// Brightness knob and the five top annunciator windows.
    private var topAnnunciators: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.97), Color(white: 0.70)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 1, endRadius: 14))
                .frame(width: 24, height: 24)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            ForEach(0..<5, id: \.self) { _ in
                Capsule()
                    .fill(Color(white: 0.10))
                    .overlay(Capsule().stroke(Color.black.opacity(0.6), lineWidth: 1))
                    .frame(width: 46, height: 14)
            }
        }
        .padding(.top, 4)
    }

    // MARK: Screen with line select keys

    private var screenRow: some View {
        HStack(spacing: 0) {
            lskColumn(side: "L")
            connectorColumn(alignment: .leading)
            MCDUScreenView(screen: model.mcduScreen, connected: model.status == .connected)
            connectorColumn(alignment: .trailing)
            lskColumn(side: "R")
        }
    }

    /// Centre of data line `n` (1…6) from the top of the screen: the LSK sits beside it.
    private func lineCenter(_ line: Int) -> CGFloat {
        MCDUMetrics.screenPadding + (CGFloat(line * 2) + 0.5) * MCDUMetrics.rowHeight
    }

    private func lskColumn(side: String) -> some View {
        ZStack(alignment: .top) {
            Color.clear
            ForEach(1...6, id: \.self) { line in
                MCDUKey(width: MCDUMetrics.lskSize.width, height: MCDUMetrics.lskSize.height) {
                    Capsule().fill(Color.white.opacity(0.85)).frame(width: 18, height: 2.5)
                } action: {
                    model.pressMCDU("LSK\(line)\(side)")
                }
                .offset(y: lineCenter(line) - MCDUMetrics.lskSize.height / 2)
            }
        }
        .frame(width: MCDUMetrics.lskSize.width, height: MCDUMetrics.screenHeight)
    }

    /// The short white lines between each LSK and the screen edge.
    private func connectorColumn(alignment: Alignment) -> some View {
        ZStack(alignment: .top) {
            Color.clear
            ForEach(1...6, id: \.self) { line in
                Rectangle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 14, height: 1.5)
                    .offset(y: lineCenter(line))
            }
        }
        .frame(width: 16, height: MCDUMetrics.screenHeight, alignment: alignment)
    }

    // MARK: Page keys

    private var pageKeys: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    pageKey("DIR", "DirTo")
                    pageKey("PROG", "Prog")
                    pageKey("PERF", "Perf")
                    pageKey("INIT", "Init")
                    pageKey("DATA", "Data")
                    blankKey
                }
                HStack(spacing: 7) {
                    pageKey("F-PLN", "Fpln")
                    pageKey("RAD\nNAV", "RadNav")
                    pageKey("FUEL\nPRED", "FuelPred")
                    pageKey("SEC\nF-PLN", "SecFpln")
                    pageKey("ATC\nCOMM", "ATC")
                    pageKey("MCDU\nMENU", "Menu")
                }
            }
            VStack(spacing: 0) {
                pageKey("BRT", "KeyBright", width: 42, height: 33)
                pageKey("DIM", "KeyDim", width: 42, height: 33)
            }
        }
    }

    private func pageKey(_ title: String, _ command: String, width: CGFloat = 62, height: CGFloat = 33) -> some View {
        MCDUKey(width: width, height: height) {
            Text(title)
                .font(.system(size: title.contains("\n") ? 9 : 11, weight: .bold))
                .fontWidth(.condensed)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .foregroundStyle(.white)
        } action: {
            model.pressMCDU(command)
        }
    }

    private var blankKey: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(white: 0.16))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.6), lineWidth: 1))
            .frame(width: 62, height: 33)
    }

    // MARK: Lower keyboard

    private var lowerKeyboard: some View {
        HStack(alignment: .top, spacing: 16) {
            annunciatorStrip(["FAIL", "FM", "MCDU\nMENU"])
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    pageKey("AIR\nPORT", "Airport")
                    blankKey
                }
                slewKeys
                numericPad
            }
            alphaPad
            annunciatorStrip(["FM1", "IND", "RDY", "FM2"])
        }
    }

    private var slewKeys: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                slewKey("arrowtriangle.left.fill", "SlewLeft")
                slewKey("arrowtriangle.up.fill", "SlewUp")
            }
            HStack(spacing: 4) {
                slewKey("arrowtriangle.right.fill", "SlewRight")
                slewKey("arrowtriangle.down.fill", "SlewDown")
            }
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.25)))
    }

    private func slewKey(_ symbol: String, _ command: String) -> some View {
        MCDUKey(width: 62, height: 28) {
            Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(.white)
        } action: {
            model.pressMCDU(command)
        }
    }

    private var numericPad: some View {
        let rows: [[MCDUKeyDef]] = [
            [MCDUKeyDef("1", "Key1"), MCDUKeyDef("2", "Key2"), MCDUKeyDef("3", "Key3")],
            [MCDUKeyDef("4", "Key4"), MCDUKeyDef("5", "Key5"), MCDUKeyDef("6", "Key6")],
            [MCDUKeyDef("7", "Key7"), MCDUKeyDef("8", "Key8"), MCDUKeyDef("9", "Key9")],
            [MCDUKeyDef(".", "KeyDecimal"), MCDUKeyDef("0", "Key0"), MCDUKeyDef("+/-", "KeyPM")],
        ]
        return VStack(spacing: 11) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 13) {
                    ForEach(rows[row]) { key in
                        MCDUKey(width: 38, height: 38, round: true) {
                            Text(key.title)
                                .font(.system(size: key.title.count > 1 ? 11 : 16, weight: .bold))
                                .foregroundStyle(.white)
                        } action: {
                            model.pressMCDU(key.command)
                        }
                    }
                }
            }
        }
        .padding(.leading, 6)
    }

    private var alphaPad: some View {
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXY").map(String.init)
        let rows = stride(from: 0, to: letters.count, by: 5).map { Array(letters[$0..<min($0 + 5, letters.count)]) }
        return VStack(spacing: 9) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 9) {
                    ForEach(rows[row], id: \.self) { letter in
                        alphaKey(letter, "Key\(letter)")
                    }
                }
            }
            HStack(spacing: 9) {
                alphaKey("Z", "KeyZ")
                alphaKey("/", "KeySlash")
                alphaKey("SP", "KeySpace")
                MCDUKey(width: 40, height: 40) {
                    VStack(spacing: 0) {
                        Text("OVFY").font(.system(size: 8, weight: .bold))
                        Image(systemName: "triangle").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                } action: {
                    model.pressMCDU("KeyOverfly")
                }
                alphaKey("CLR", "KeyClear")
            }
        }
    }

    private func alphaKey(_ title: String, _ command: String) -> some View {
        MCDUKey(width: 40, height: 40) {
            Text(title)
                .font(.system(size: title.count > 1 ? 12 : 17, weight: .bold))
                .foregroundStyle(.white)
        } action: {
            model.pressMCDU(command)
        }
    }

    /// Dark vertical annunciator window beside the keyboard (lit by the FMGC in the aircraft).
    private func annunciatorStrip(_ labels: [String]) -> some View {
        VStack(spacing: 6) {
            ForEach(labels, id: \.self) { label in
                Text(label)
                    .font(.system(size: 7, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color(white: 0.32))
                    .frame(width: 26, height: 30)
            }
        }
        .padding(.vertical, 6)
        .background(Capsule().fill(Color(white: 0.09)))
        .overlay(Capsule().stroke(Color.black.opacity(0.6), lineWidth: 1))
        .padding(.top, 40)
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
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.03, green: 0.03, blue: 0.04))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black, lineWidth: 3))
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
            if !connected && screen.isBlank {
                Text("SIN CONEXIÓN")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(white: 0.35))
            }
        }
        .frame(width: MCDUMetrics.screenWidth, height: MCDUMetrics.screenHeight)
    }

    private func cell(_ cell: MCDUCell) -> some View {
        Text(String(cell.character))
            .font(.system(size: cell.small ? 15 : 20, weight: .medium, design: .monospaced))
            .foregroundStyle(color(cell.color))
            .frame(width: MCDUMetrics.cellWidth, height: MCDUMetrics.rowHeight,
                   alignment: cell.small ? .bottom : .center)
    }

    private func color(_ color: MCDUColor) -> Color {
        switch color {
        case .white: return Color(white: 0.96)
        case .cyan: return Color(red: 0.20, green: 0.90, blue: 1.00)
        case .green: return Color(red: 0.25, green: 1.00, blue: 0.35)
        case .magenta: return Color(red: 1.00, green: 0.35, blue: 1.00)
        case .amber: return Color(red: 1.00, green: 0.60, blue: 0.10)
        case .yellow: return Color(red: 1.00, green: 0.95, blue: 0.20)
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

/// MCDU key: dark cap with a top highlight that sinks while touched.
private struct MCDUKey<Label: View>: View {
    let width: CGFloat
    let height: CGFloat
    var round = false
    @ViewBuilder let label: () -> Label
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if round {
                    Circle().fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.06)],
                                                 startPoint: .top, endPoint: .bottom))
                    Circle().stroke(Color.black.opacity(0.8), lineWidth: 1)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.10)],
                                             startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.8), lineWidth: 1)
                }
                label()
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(KorryPressStyle())
    }
}

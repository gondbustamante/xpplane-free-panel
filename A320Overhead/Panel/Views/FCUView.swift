import SwiftUI
import XPlaneKit

/// The glareshield FCU: one column per selector (window + knob + its buttons) with the AP1 / AP2 /
/// A/THR block after the second selector, as on the real unit. Everything it reads and fires comes
/// from `mapping/fcu/fcu.json`.
struct FCUView: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        Group {
            if let fcu = model.fcu {
                panel(fcu)
            } else {
                Text("No hay mapeo del FCU. Añade mapping/fcu/fcu.json.")
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(40)
            }
        }
    }

    private func panel(_ fcu: FCUDefinition) -> some View {
        let centerAfter = fcu.selectors.count >= 3 ? 1 : fcu.selectors.count - 1
        return HStack(alignment: .top, spacing: 26) {
            ForEach(Array(fcu.selectors.enumerated()), id: \.element.id) { index, selector in
                FCUSelectorColumn(selector: selector, buttons: fcu.buttons(in: selector.id))
                if index == centerAfter {
                    FCUCenterColumn(buttons: fcu.buttons(in: "center"))
                }
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [PanelTheme.panelFaceHighlight, PanelTheme.panelFace],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
        )
        .overlay(alignment: .topLeading) {
            Text(fcu.title.uppercased())
                .font(.system(size: 12.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .background(PanelTheme.panelFace)
                .offset(x: 18, y: -9)
        }
    }
}

/// Window + knob + the buttons mapped to this selector's column.
struct FCUSelectorColumn: View {
    let selector: FCUSelectorDefinition
    let buttons: [FCUButtonDefinition]
    @Environment(PanelModel.self) private var model

    @State private var entryShown = false
    @State private var entryText = ""
    @State private var entryRejected = false

    private var modeOn: Bool { model.isOn(selector.mode) }
    private var format: FCUFormat { selector.activeFormat(modeOn: modeOn) }
    private var enabled: Bool { model.isAvailable(selector) }

    private var windowText: String {
        guard model.isFCUPowered else { return "" }
        if model.isOn(selector.dashed) { return format.dashes }
        return format.text(for: model.displayedValue(of: selector))
    }

    var body: some View {
        VStack(spacing: 10) {
            modeLabels
            FCUWindowView(text: windowText,
                          managed: model.isFCUPowered && model.isOn(selector.managed),
                          verified: selector.isVerified || !model.showVerificationBadges,
                          enabled: enabled) {
                entryText = ""
                entryRejected = false
                entryShown = true
            }
            FCUKnobView(enabled: enabled,
                        hasPush: selector.commands?.push != nil,
                        hasPull: selector.commands?.pull != nil,
                        onTurn: { steps in model.turn(selector, steps: steps) },
                        onPush: { model.push(selector) },
                        onPull: { model.pull(selector) })
            ForEach(buttons) { button in
                FCUButtonCell(button: button)
            }
        }
        .alert("Ajustar \(selector.activeLabel(modeOn: modeOn))", isPresented: $entryShown) {
            TextField(format.text(for: model.displayedValue(of: selector)), text: $entryText)
                .keyboardType(.numbersAndPunctuation)
            Button("Enviar") {
                if !model.set(selector, to: entryText) { entryRejected = true }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text(entryHint)
        }
        .alert("Valor no válido", isPresented: $entryRejected) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Escribe un número, por ejemplo \(format.text(for: exampleValue)).")
        }
    }

    private var modeLabels: some View {
        HStack(spacing: 10) {
            PanelLabel(text: selector.label)
                .opacity(modeOn && selector.alternateLabel != nil ? 0.35 : 1)
            if let alternate = selector.alternateLabel {
                PanelLabel(text: alternate)
                    .opacity(modeOn ? 1 : 0.35)
            }
        }
    }

    private var entryHint: String {
        var parts: [String] = ["Se escribe directamente en \(selector.writeBinding.dataref)."]
        if let range = selector.activeRange(modeOn: modeOn) {
            parts.append("Rango \(format.text(for: range.min)) a \(format.text(for: range.max)).")
        }
        return parts.joined(separator: " ")
    }

    private var exampleValue: Double {
        switch format {
        case .speed: return 250
        case .mach: return 0.78
        case .heading: return 90
        case .altitude: return 5000
        case .verticalSpeed: return -1500
        case .flightPathAngle: return -3
        }
    }
}

/// Black LCD-style window with amber digits and the managed dot. Tap to type a value.
struct FCUWindowView: View {
    let text: String
    let managed: Bool
    let verified: Bool
    let enabled: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(text.isEmpty ? " " : text)
                .font(.system(size: 30, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelTheme.fcuDigits)
                .shadow(color: PanelTheme.fcuDigits.opacity(0.6), radius: 4)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Circle()
                .fill(managed ? PanelTheme.fcuDigits : Color.white.opacity(0.08))
                .frame(width: 9, height: 9)
                .shadow(color: managed ? PanelTheme.fcuDigits.opacity(0.8) : .clear, radius: 3)
        }
        .padding(.horizontal, 12)
        .frame(width: 150, height: 54)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(white: 0.03), Color(white: 0.09)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(white: 0.5), lineWidth: 1.2))
        .overlay(alignment: .topTrailing) {
            if !verified {
                Circle()
                    .fill(PanelTheme.verificationBadge)
                    .frame(width: 7, height: 7)
                    .offset(x: 4, y: -4)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// Column for AP1, AP2 (side by side) and A/THR underneath, mirroring the real layout.
struct FCUCenterColumn: View {
    let buttons: [FCUButtonDefinition]

    var body: some View {
        VStack(spacing: 10) {
            Color.clear.frame(height: 14)   // align with the mode labels of the selector columns
            if buttons.count >= 2 {
                HStack(spacing: 10) {
                    FCUButtonCell(button: buttons[0])
                    FCUButtonCell(button: buttons[1])
                }
                ForEach(buttons.dropFirst(2)) { button in
                    FCUButtonCell(button: button)
                }
            } else {
                ForEach(buttons) { button in
                    FCUButtonCell(button: button)
                }
            }
        }
    }
}

/// Picks the widget for a button definition and wires it to the model.
struct FCUButtonCell: View {
    let button: FCUButtonDefinition
    @Environment(PanelModel.self) private var model

    var body: some View {
        ZStack(alignment: .topTrailing) {
            switch button.resolvedKind {
            case .push:
                FCUPushButtonView(label: button.label,
                                  sublabel: button.sublabel,
                                  lit: model.isLit(button),
                                  enabled: model.isAvailable(button)) {
                    model.press(button)
                }
            case .toggle:
                FCUToggleView(label: button.label,
                              positions: button.positions ?? ["0", "1"],
                              position: model.position(of: button),
                              enabled: model.isAvailable(button)) {
                    model.press(button)
                }
            }
            if model.showVerificationBadges && !button.isVerified {
                Circle()
                    .fill(PanelTheme.verificationBadge)
                    .frame(width: 7, height: 7)
                    .offset(x: 5, y: -3)
            }
        }
    }
}

/// Square FCU pushbutton: white legend, three green bars when engaged, depresses while touched.
struct FCUPushButtonView: View {
    let label: String
    var sublabel: String?
    let lit: Bool
    let enabled: Bool
    let onPress: () -> Void

    @State private var pressed = false

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(lit ? PanelTheme.lamp("green") : Color.white.opacity(0.08))
                        .frame(width: 12, height: 3)
                        .shadow(color: lit ? PanelTheme.lamp("green").opacity(0.9) : .clear, radius: 3)
                }
            }
            Text(label)
                .font(.system(size: 10.5, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let sublabel {
                Text(sublabel)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .frame(width: 66, height: 50)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(white: 0.20), Color(white: 0.10)],
                                     startPoint: .top, endPoint: .bottom))
        )
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(white: 0.45), lineWidth: 1.2))
        .shadow(color: .black.opacity(pressed ? 0.15 : 0.55), radius: pressed ? 1 : 3, y: pressed ? 0.5 : 2.5)
        .scaleEffect(pressed ? 0.965 : 1)
        .offset(y: pressed ? 1.5 : 0)
        .animation(.easeOut(duration: 0.08), value: pressed)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true } }
                .onEnded { _ in
                    pressed = false
                    onPress()
                }
        )
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

/// Two-position rocker (e.g. ALT 100 / 1000). Tap to flip; the active legend is highlighted.
struct FCUToggleView: View {
    let label: String
    let positions: [String]
    let position: Int
    let enabled: Bool
    let onFlip: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            PanelLabel(text: label, small: true)
            HStack(spacing: 0) {
                ForEach(Array(positions.enumerated()), id: \.offset) { index, name in
                    Text(name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(index == position ? Color.black : Color.white.opacity(0.8))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(index == position ? Color.white.opacity(0.9) : Color(white: 0.16))
                }
            }
            .frame(width: 66)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(white: 0.45), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { onFlip() }
            .animation(.easeOut(duration: 0.1), value: position)
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }
}

#Preview {
    HStack(spacing: 20) {
        FCUWindowView(text: "250", managed: true, verified: false, enabled: true) {}
        FCUWindowView(text: "+25oo", managed: false, verified: true, enabled: true) {}
        FCUPushButtonView(label: "AP1", lit: true, enabled: true) {}
        FCUPushButtonView(label: "HDG V/S", sublabel: "TRK FPA", lit: false, enabled: true) {}
        FCUToggleView(label: "ALT STEP", positions: ["100", "1000"], position: 1, enabled: true) {}
    }
    .padding(30)
    .background(PanelTheme.panelFace)
}

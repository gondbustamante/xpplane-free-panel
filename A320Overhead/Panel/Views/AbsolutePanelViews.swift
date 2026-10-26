import SwiftUI
import XPlaneKit

/// Points per canvas unit. The overhead canvas is 828 × 633 units (the proportions of the
/// real panel), so one unit is roughly 1.3 mm of aircraft.
enum PanelMetrics {
    static let unit: CGFloat = 2.5
    static func pt(_ units: Double) -> CGFloat { CGFloat(units) * unit }
    /// Default body sizes in units.
    static let korrySide: Double = 17
    static let roundButton: Double = 14
    static let toggleBezel: Double = 18
    static let rotaryDiameter: Double = 26
    static let knobDiameter: Double = 26
    static let fireWidth: Double = 44
    static let fireHeight: Double = 27
    static let displayWidth: Double = 32
    static let displayHeight: Double = 12
    /// Gap between a control body and its label, in points.
    static let labelGap: CGFloat = 7
}

/// Draws the visible subpanels of a group at their true frames, cropped to their bounding box
/// so a flight phase shows just its region of the overhead without acres of empty plate.
struct AbsoluteGroupView: View {
    let canvas: CanvasSize
    let panels: [SubpanelDefinition]

    private var bounds: CGRect {
        let frames = panels.compactMap(\.frame)
        guard let first = frames.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x + first.w, maxY = first.y + first.h
        for frame in frames.dropFirst() {
            minX = min(minX, frame.x); minY = min(minY, frame.y)
            maxX = max(maxX, frame.x + frame.w); maxY = max(maxY, frame.y + frame.h)
        }
        let margin = 6.0
        return CGRect(x: minX - margin, y: minY - margin, width: maxX - minX + 2 * margin, height: maxY - minY + 2 * margin)
    }

    var body: some View {
        let box = bounds
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(PanelTheme.panelGap)
                .frame(width: PanelMetrics.pt(box.width), height: PanelMetrics.pt(box.height))
            ForEach(panels.filter { $0.frame != nil }) { panel in
                let frame = panel.frame!
                AbsoluteSubpanelView(panel: panel)
                    .frame(width: PanelMetrics.pt(frame.w), height: PanelMetrics.pt(frame.h))
                    .position(x: PanelMetrics.pt(frame.x - box.minX + frame.w / 2),
                              y: PanelMetrics.pt(frame.y - box.minY + frame.h / 2))
            }
        }
        .frame(width: PanelMetrics.pt(box.width), height: PanelMetrics.pt(box.height), alignment: .topLeading)
    }
}

/// One plate of the overhead: face, screws, title, synoptic artwork and controls at fixed positions.
struct AbsoluteSubpanelView: View {
    let panel: SubpanelDefinition
    @Environment(PanelModel.self) private var model
    @Environment(\.backlight) private var backlight

    var body: some View {
        let frame = panel.frame!
        let width = PanelMetrics.pt(frame.w)
        let height = PanelMetrics.pt(frame.h)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(LinearGradient(colors: [PanelTheme.panelFaceHighlight, PanelTheme.panelFace],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1)
            ScrewView(size: 7).position(x: 9, y: 9)
            ScrewView(size: 7).position(x: width - 9, y: 9)
            ScrewView(size: 7).position(x: 9, y: height - 9)
            ScrewView(size: 7).position(x: width - 9, y: height - 9)

            DecorationLayer(decorations: panel.decorations ?? [])

            if panel.titleHidden != true {
                let at = panel.titleAt ?? [frame.w / 2, 5]
                Text(panel.title.uppercased())
                    .font(.system(size: 11.5, weight: .bold))
                    .fontWidth(.condensed)
                    .tracking(0.6)
                    .foregroundStyle(PanelTheme.legend(backlight))
                    .backlit()
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .padding(.horizontal, 3)
                    .background(PanelTheme.panelFace.opacity(0.9))
                    .position(x: PanelMetrics.pt(at[0]), y: PanelMetrics.pt(at[1]))
            }

            ForEach(panel.controls) { control in
                AbsoluteControlView(control: control)
                    .position(x: PanelMetrics.pt(control.x ?? 0), y: PanelMetrics.pt(control.y ?? 0))
            }
        }
        .frame(width: width, height: height)
    }
}

/// Synoptic lines, arrows, boxed labels and dividers, drawn with Canvas in canvas units.
struct DecorationLayer: View {
    let decorations: [Decoration]

    var body: some View {
        Canvas { context, _ in
            for deco in decorations {
                draw(deco, in: &context)
            }
        }
        .backlit()   // painted lines, synoptics and legends are lit too
        .allowsHitTesting(false)
    }

    private func color(_ name: String?) -> Color {
        switch name {
        case "white": return PanelTheme.legend
        case "amber": return PanelTheme.lamp("amber")
        default: return PanelTheme.synoptic
        }
    }

    private func point(_ pair: [Double]) -> CGPoint {
        CGPoint(x: PanelMetrics.pt(pair[0]), y: PanelMetrics.pt(pair.count > 1 ? pair[1] : 0))
    }

    private func draw(_ deco: Decoration, in context: inout GraphicsContext) {
        let stroke = color(deco.color)
        let lineWidth = CGFloat(deco.width ?? (deco.type == "divider" ? 0.7 : 1.1)) * PanelMetrics.unit * 0.6
        switch deco.type {
        case "line", "divider":
            guard let points = deco.points, points.count >= 2 else { return }
            var path = Path()
            path.move(to: point(points[0]))
            for pair in points.dropFirst() { path.addLine(to: point(pair)) }
            context.stroke(path, with: .color(deco.type == "divider" ? color("white") : stroke),
                           style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        case "bracket":
            guard let points = deco.points, points.count == 2 else { return }
            let a = point(points[0]), b = point(points[1])
            let tick = PanelMetrics.pt(3)
            var path = Path()
            path.move(to: a); path.addLine(to: b)
            path.move(to: a); path.addLine(to: CGPoint(x: a.x, y: a.y + tick))
            path.move(to: b); path.addLine(to: CGPoint(x: b.x, y: b.y + tick))
            context.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        case "arrow":
            guard let at = deco.at else { return }
            let tip = point(at)
            let s = PanelMetrics.pt(2.6)
            var path = Path()
            switch deco.direction ?? "up" {
            case "down":
                path.move(to: tip); path.addLine(to: CGPoint(x: tip.x - s, y: tip.y - s * 1.6)); path.addLine(to: CGPoint(x: tip.x + s, y: tip.y - s * 1.6))
            case "left":
                path.move(to: tip); path.addLine(to: CGPoint(x: tip.x + s * 1.6, y: tip.y - s)); path.addLine(to: CGPoint(x: tip.x + s * 1.6, y: tip.y + s))
            case "right":
                path.move(to: tip); path.addLine(to: CGPoint(x: tip.x - s * 1.6, y: tip.y - s)); path.addLine(to: CGPoint(x: tip.x - s * 1.6, y: tip.y + s))
            default:
                path.move(to: tip); path.addLine(to: CGPoint(x: tip.x - s, y: tip.y + s * 1.6)); path.addLine(to: CGPoint(x: tip.x + s, y: tip.y + s * 1.6))
            }
            path.closeSubpath()
            context.fill(path, with: .color(stroke))
        case "box", "text":
            guard let at = deco.at, let string = deco.text else { return }
            let size = CGFloat(deco.size ?? 5.2) * PanelMetrics.unit * 0.72
            let text = Text(string.uppercased())
                .font(.system(size: size, weight: .semibold)).fontWidth(.condensed)
                .foregroundColor(color(deco.color ?? "white"))
            let resolved = context.resolve(text)
            let measured = resolved.measure(in: CGSize(width: 1000, height: 1000))
            let center = point(at)
            if deco.vertical == true {
                context.drawLayer { layer in
                    layer.translateBy(x: center.x, y: center.y)
                    layer.rotate(by: .degrees(90))
                    layer.draw(resolved, at: .zero, anchor: .center)
                }
            } else {
                context.draw(resolved, at: center, anchor: .center)
            }
            if deco.type == "box" {
                let padX = PanelMetrics.pt(2.2), padY = PanelMetrics.pt(1.0)
                let rect = CGRect(x: center.x - measured.width / 2 - padX, y: center.y - measured.height / 2 - padY,
                                  width: measured.width + 2 * padX, height: measured.height + 2 * padY)
                context.fill(Path(rect), with: .color(PanelTheme.panelFace))
                context.draw(resolved, at: center, anchor: .center)
                context.stroke(Path(rect), with: .color(color("white")), lineWidth: 1)
            }
        default:
            break
        }
    }
}

/// Places the right body view for a control; labels hang around the body as overlays so the
/// view's frame is the body itself and `x`/`y` mean the body centre.
struct AbsoluteControlView: View {
    let control: ControlDefinition
    @Environment(PanelModel.self) private var model

    private var enabled: Bool { model.isAvailable(control) }
    private var dimmed: Bool { model.isDimmed(control) }

    var body: some View {
        ZStack {
            body(for: control)
            if model.showVerificationBadges && (!control.isVerified || control.isReadOnly) {
                Image(systemName: control.isReadOnly ? "lock.fill" : "circle.fill")
                    .font(.system(size: control.isReadOnly ? 8 : 6))
                    .foregroundStyle(PanelTheme.verificationBadge)
                    .offset(x: PanelMetrics.pt((control.size ?? 22) / 2) + 4, y: -PanelMetrics.pt((control.size ?? 22) / 2) - 2)
                    .allowsHitTesting(false)
            }
        }
        // Overlay, not a ZStack layer: the ring must not change the control's size.
        .overlay {
            if model.highlightedControl == control.id {
                LocateRing(diameter: PanelMetrics.pt(control.size ?? 22) + 16)
            }
        }
        .learnTarget(control.id)
    }

    /// Tapping a radio or BARO knob opens its sheet; other dual knobs click towards the tap.
    private func knobTap(_ control: ControlDefinition) -> (() -> Void)? {
        if let radio = model.radio(containing: control) {
            return { model.openTuner(radio) }
        }
        if let baro = model.baroPanel(containing: control) {
            return { model.openBaroSheet(baro) }
        }
        return nil
    }

    @ViewBuilder
    private func body(for control: ControlDefinition) -> some View {
        switch control.kind {
        case .toggle2, .toggle3:
            ToggleSwitchView(label: control.label, positions: control.positions, position: model.position(of: control),
                             enabled: enabled, dimmed: dimmed, inline: false,
                             bezel: PanelMetrics.pt(control.size ?? PanelMetrics.toggleBezel)) { delta in
                model.move(control, by: delta)
            }
        case .rotary:
            RotarySelectorView(label: control.label, positions: control.positions, position: model.position(of: control),
                               enabled: enabled, dimmed: dimmed, inline: false,
                               diameter: PanelMetrics.pt(control.size ?? PanelMetrics.rotaryDiameter),
                               labelBelow: control.labelBelow ?? false) { delta in
                model.move(control, by: delta)
            }
        case .knob:
            KnobView(label: control.label, positions: control.positions,
                     fraction: model.fraction(of: control), enabled: enabled, dimmed: dimmed,
                     diameter: PanelMetrics.pt(control.size ?? PanelMetrics.knobDiameter)) { fraction in
                model.set(control, fraction: fraction)
            }
        case .display:
            if let baro = model.baroPanel(containing: control) {
                // BARO window: opens the QNH sheet, where the setting is typed.
                Button { model.openBaroSheet(baro) } label: {
                    DisplayView(label: control.label, text: model.displayText(of: control),
                                width: PanelMetrics.pt(control.size ?? PanelMetrics.displayWidth),
                                height: PanelMetrics.pt(PanelMetrics.displayHeight))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre el ajuste del QNH")
            } else if let radio = model.radio(containing: control) {
                // RMP windows open the tuner: typing a frequency beats turning the knob.
                Button { model.openTuner(radio) } label: {
                    DisplayView(label: control.label, text: model.displayText(of: control),
                                width: PanelMetrics.pt(control.size ?? PanelMetrics.displayWidth),
                                height: PanelMetrics.pt(PanelMetrics.displayHeight))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Abre el sintonizador")
            } else {
                DisplayView(label: control.label, text: model.displayText(of: control),
                            width: PanelMetrics.pt(control.size ?? PanelMetrics.displayWidth),
                            height: PanelMetrics.pt(PanelMetrics.displayHeight))
            }
        case .lever:
            LeverView(label: control.label, positions: control.positions, position: model.position(of: control),
                      enabled: enabled, dimmed: dimmed,
                      height: PanelMetrics.pt(control.size ?? 40)) { delta in
                model.move(control, by: delta)
            }
        case .dualKnob:
            DualKnobView(label: control.label, enabled: enabled, dimmed: dimmed,
                         diameter: PanelMetrics.pt(control.size ?? 22),
                         onTap: knobTap(control)) { small, delta in
                model.turn(control, small: small, delta: delta)
            }
        case .korry:
            switch control.style ?? "" {
            case "round":
                RoundButtonView(label: control.label, enabled: enabled, dimmed: dimmed,
                                diameter: PanelMetrics.pt(control.size ?? PanelMetrics.roundButton)) {
                    model.press(control)
                }
            case "key", "keyRed":
                let side = PanelMetrics.pt(control.size ?? 13)
                KeyButtonView(label: control.label, lit: model.isLit(control.lamps?.top),
                              lightColor: PanelTheme.lamp(control.lamps?.top?.color ?? "white"),
                              red: control.style == "keyRed", enabled: enabled, dimmed: dimmed,
                              width: side, height: side * 0.62) {
                    model.press(control)
                }
            case "fire":
                FireButtonView(label: control.label, lit: model.isLit(control.lamps?.top),
                               pushed: model.position(of: control) > 0, enabled: enabled, dimmed: dimmed,
                               width: PanelMetrics.pt(PanelMetrics.fireWidth), height: PanelMetrics.pt(PanelMetrics.fireHeight)) {
                    model.press(control)
                }
            default:
                KorryButtonView(label: control.label, top: lamp(control.lamps?.top), bottom: lamp(control.lamps?.bottom),
                                guarded: control.guarded ?? false, enabled: enabled, dimmed: dimmed,
                                guardStyle: control.guardStyle ?? "cage", sideLabel: control.sideLabel, inline: false,
                                size: PanelMetrics.pt(control.size ?? PanelMetrics.korrySide),
                                labelBelow: control.labelBelow ?? false) {
                    model.press(control)
                }
            }
        }
    }

    private func lamp(_ definition: Lamp?) -> KorryLamp? {
        guard let definition else { return nil }
        return KorryLamp(text: definition.text, color: PanelTheme.lamp(definition.color), lit: model.isLit(definition))
    }
}

/// Label text used above controls in absolute mode.
struct ControlLabel: View {
    let text: String
    var size: CGFloat = 8
    @Environment(\.backlight) private var level

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .semibold))
            .fontWidth(.condensed)
            .tracking(0.3)
            .foregroundStyle(PanelTheme.legend(level))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize()
            .backlit()
    }
}

/// Continuous knob: light grey with a pointer line, 270° sweep. Drag horizontally or around it.
struct KnobView: View {
    let label: String
    /// Legends at the ends: [min, max], e.g. ["COLD", "HOT"].
    let positions: [String]
    let fraction: Double
    let enabled: Bool
    let dimmed: Bool
    let diameter: CGFloat
    let onChange: (Double) -> Void

    @State private var dragStart: Double?

    private var angle: Double { -135 + 270 * min(max(fraction, 0), 1) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 1)
                .frame(width: diameter * 1.25, height: diameter * 1.25)
                .mask(
                    Circle().trim(from: 0.125, to: 0.875)
                        .stroke(style: StrokeStyle(lineWidth: 2))
                        .rotationEffect(.degrees(90))
                        .frame(width: diameter * 1.25, height: diameter * 1.25)
                )
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.92), Color(white: 0.62)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 1, endRadius: diameter * 0.6))
                .frame(width: diameter, height: diameter)
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
            Capsule()
                .fill(Color(white: 0.25))
                .frame(width: 2.5, height: diameter * 0.42)
                .offset(y: -diameter * 0.25)
                .rotationEffect(.degrees(angle))
        }
        .frame(width: diameter * 1.3, height: diameter * 1.3)
        .overlay(alignment: .top) { ControlLabel(text: label).offset(y: -PanelMetrics.labelGap - 4) }
        .overlay(alignment: .bottomLeading) {
            if let first = positions.first { ControlLabel(text: first, size: 7).offset(x: -14, y: 2) }
        }
        .overlay(alignment: .bottomTrailing) {
            if positions.count > 1 { ControlLabel(text: positions[positions.count - 1], size: 7).offset(x: 14, y: 2) }
        }
        .opacity(dimmed ? 0.5 : 1)
        .contentShape(Circle())
        .animation(.easeOut(duration: 0.12), value: fraction)
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if dragStart == nil { dragStart = fraction }
                    let delta = Double(value.translation.width - value.translation.height) / 220
                    onChange(min(max((dragStart ?? fraction) + delta, 0), 1))
                }
                .onEnded { _ in dragStart = nil }
        )
        .disabled(!enabled)
    }
}

/// Amber digits in a black window (battery voltmeters).
struct DisplayView: View {
    let label: String
    let text: String
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.black)
                .overlay(RoundedRectangle(cornerRadius: 2).stroke(PanelTheme.bezel, lineWidth: 1.5))
            Text(text)
                .font(.system(size: height * 0.62, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(PanelTheme.fcuDigitsColor)
                .shadow(color: PanelTheme.fcuDigitsColor.opacity(0.7), radius: 2)
        }
        .frame(width: width, height: height)
        .overlay(alignment: .top) { if !label.isEmpty { ControlLabel(text: label).offset(y: -PanelMetrics.labelGap - 4) } }
    }
}

/// Round black momentary pushbutton (CALLS, CVR TEST, fire TEST, RAIN RPLNT).
struct RoundButtonView: View {
    let label: String
    let enabled: Bool
    let dimmed: Bool
    let diameter: CGFloat
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            ZStack {
                Circle().fill(RadialGradient(colors: [Color(white: 0.20), Color(white: 0.04)],
                                             center: .center, startRadius: 1, endRadius: diameter * 0.55))
                Circle().stroke(Color(white: 0.35), lineWidth: 1)
                Circle().stroke(Color(white: 0.28), lineWidth: 1).frame(width: diameter * 0.62, height: diameter * 0.62)
                Circle().fill(Color(white: 0.30)).frame(width: diameter * 0.14, height: diameter * 0.14)
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(KorryPressStyle())
        .overlay(alignment: .top) { ControlLabel(text: label).offset(y: -PanelMetrics.labelGap - 4) }
        .opacity(dimmed ? 0.5 : 1)
        .disabled(!enabled)
    }
}

/// Red guarded fire pushbutton (ENG 1 / APU / ENG 2). Lit red when the loop detects fire.
struct FireButtonView: View {
    @Environment(\.backlight) private var backlight
    let label: String
    let lit: Bool
    let pushed: Bool
    let enabled: Bool
    let dimmed: Bool
    let width: CGFloat
    let height: CGFloat
    let onPress: () -> Void

    @State private var guardOpen = false

    var body: some View {
        ZStack(alignment: .top) {
            Button(action: { onPress(); guardOpen = false }) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(lit ? Color(red: 0.95, green: 0.12, blue: 0.08) : Color(red: 0.30, green: 0.10, blue: 0.10))
                    .overlay(
                        Text(lit ? "FIRE" : "")
                            .font(.system(size: height * 0.42, weight: .heavy)).fontWidth(.condensed)
                            .foregroundStyle(.white)
                            .shadow(color: .red, radius: lit ? 6 : 0)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.7), lineWidth: 1))
                    .shadow(color: lit ? .red.opacity(0.8) : .clear, radius: 8)
                    .padding(5)
                    .frame(width: width, height: height)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.80, green: 0.14, blue: 0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.6), lineWidth: 1))
                    .scaleEffect(pushed ? 0.95 : 1)
            }
            .buttonStyle(KorryPressStyle())
            .disabled(!enabled || !guardOpen)

            // Red hinged guard with a black latch strip, as on the aircraft.
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color(red: 0.92, green: 0.22, blue: 0.18), Color(red: 0.72, green: 0.10, blue: 0.08)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.6), lineWidth: 1))
                RoundedRectangle(cornerRadius: 1.5).fill(Color.black).frame(width: width * 0.5, height: 4).padding(.top, 4)
            }
            .frame(width: width, height: height)
            .rotation3DEffect(.degrees(guardOpen ? -110 : 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.6)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: guardOpen)
            .allowsHitTesting(!guardOpen)
            .onTapGesture { if enabled { guardOpen = true } }
        }
        .frame(width: width, height: height)
        .overlay(alignment: .top) {
            Text(label.uppercased()).font(.system(size: 12, weight: .bold)).fontWidth(.condensed)
                .foregroundStyle(PanelTheme.legend(backlight)).backlit().fixedSize().offset(y: -14)
        }
        .opacity(dimmed ? 0.5 : 1)
        .onChange(of: guardOpen) { _, open in
            if open {
                Task { try? await Task.sleep(for: .seconds(8)); guardOpen = false }
            }
        }
    }
}

/// Rectangular pushbutton with its legend on the key and a light bar on top (ECAM control
/// panel). `red` draws the red face of EMER CANC.
struct KeyButtonView: View {
    @Environment(\.backlight) private var backlight
    let label: String
    let lit: Bool
    let lightColor: Color
    let red: Bool
    let enabled: Bool
    let dimmed: Bool
    let width: CGFloat
    let height: CGFloat
    let onPress: () -> Void

    var body: some View {
        Button(action: onPress) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: red
                                         ? [Color(red: 0.62, green: 0.18, blue: 0.20), Color(red: 0.42, green: 0.10, blue: 0.12)]
                                         : [Color(white: 0.20), Color(white: 0.07)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.85), lineWidth: 1))
                RoundedRectangle(cornerRadius: 1)
                    .fill(lit ? lightColor : Color(white: 0.22))
                    .frame(width: width * 0.40, height: max(height * 0.11, 2.5))
                    .shadow(color: lit ? lightColor.opacity(0.9) : .clear, radius: 3)
                    .padding(.top, height * 0.12)
                Text(label)
                    .font(.system(size: height * (label.contains("\n") ? 0.24 : 0.32), weight: .bold))
                    .fontWidth(.condensed)
                    .multilineTextAlignment(.center)
                    .lineSpacing(-1)
                    .foregroundStyle(red ? Color(red: 1.0, green: 0.78, blue: 0.78) : PanelTheme.legend(backlight))
                    .backlit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, height * 0.22)
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
        }
        .buttonStyle(KorryPressStyle())
        .opacity(dimmed ? 0.5 : 1)
        .disabled(!enabled)
    }
}

/// Long-travel lever with labelled detents (flaps, speed brake). Positions run bottom → top.
/// Tap above or below the handle to move one detent, or drag the handle.
struct LeverView: View {
    let label: String
    let positions: [String]
    let position: Int
    let enabled: Bool
    let dimmed: Bool
    let height: CGFloat
    let onMove: (Int) -> Void

    @State private var dragStart: Int?

    private var count: Int { max(positions.count, 2) }
    private var step: CGFloat { height / CGFloat(count - 1) }

    /// Vertical position of detent `index` measured from the top of the slot.
    private func y(_ index: Int) -> CGFloat {
        height - CGFloat(index) * step
    }

    var body: some View {
        let current = min(max(position, 0), count - 1)
        let handleHeight = max(height * 0.22, 18)
        return ZStack(alignment: .top) {
            // Slot and detent ticks with their legends on the left.
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.black.opacity(0.85))
                .frame(width: 12, height: height + handleHeight * 0.4)
                .offset(y: -handleHeight * 0.2)
            ForEach(0..<count, id: \.self) { index in
                HStack(spacing: 4) {
                    ControlLabel(text: positions[index], size: 7)
                        .frame(width: 34, alignment: .trailing)
                    Rectangle().fill(PanelTheme.legend).frame(width: 8, height: 1.2).backlit()
                }
                .offset(x: -30, y: y(index) - 5)
            }
            // Handle.
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [Color(white: 0.28), Color(white: 0.08)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.8), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
                .frame(width: 44, height: handleHeight)
                .offset(y: y(current) - handleHeight / 2)
                .animation(.spring(response: 0.22, dampingFraction: 0.75), value: position)
        }
        .frame(width: 60, height: height, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { location in
            onMove(location.y < y(current) ? 1 : -1)
        }
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { value in
                    if dragStart == nil { dragStart = current }
                    let target = (dragStart ?? current) + Int((-value.translation.height / step).rounded())
                    let clamped = min(max(target, 0), count - 1)
                    if clamped != current { onMove(clamped - current) }
                }
                .onEnded { _ in dragStart = nil }
        )
        .overlay(alignment: .top) {
            if !label.isEmpty { ControlLabel(text: label).offset(y: -handleHeight / 2 - 14) }
        }
        .opacity(dimmed ? 0.5 : 1)
        .disabled(!enabled)
    }
}

/// Concentric frequency knob (RMP): the outer ring changes the large step, the inner cap the
/// small step. Tap the right or left half to turn one click, or drag horizontally.
struct DualKnobView: View {
    let label: String
    let enabled: Bool
    let dimmed: Bool
    let diameter: CGFloat
    /// Tap: opens the radio tuner when set; otherwise one click towards the tapped side.
    var onTap: (() -> Void)? = nil
    let onTurn: (_ small: Bool, _ delta: Int) -> Void

    @State private var lastStep: Int = 0
    @State private var dragIsInner = false
    @State private var dragging = false
    /// Drawn rotation of each part, so a click is seen as well as heard in the sim.
    @State private var outerAngle: Double = 0
    @State private var innerAngle: Double = 0

    /// Finger travel per click. Right or up turns clockwise (increase), left or down decreases.
    private let clickDistance: CGFloat = 12

    var body: some View {
        ZStack {
            // Outer ring with knurling.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.30), Color(white: 0.10)],
                                     center: .center, startRadius: diameter * 0.2, endRadius: diameter * 0.55))
                .overlay(Circle().stroke(dragging && !dragIsInner ? PanelTheme.checklistCyan : Color.black.opacity(0.8),
                                         lineWidth: dragging && !dragIsInner ? 1.5 : 1))
            ZStack {
                ForEach(0..<24, id: \.self) { index in
                    Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1, height: diameter * 0.12)
                        .offset(y: -diameter * 0.44).rotationEffect(.degrees(Double(index) * 15))
                }
            }
            .rotationEffect(.degrees(outerAngle))
            // Inner cap with its index mark.
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.92), Color(white: 0.66)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 1, endRadius: diameter * 0.32))
                .overlay(alignment: .top) {
                    Capsule().fill(Color(white: 0.35)).frame(width: max(diameter * 0.04, 1), height: diameter * 0.14)
                        .padding(.top, diameter * 0.04)
                }
                .rotationEffect(.degrees(innerAngle))
                .overlay(Circle().stroke(dragging && dragIsInner ? PanelTheme.checklistCyan : .clear, lineWidth: 1.5))
                .frame(width: diameter * 0.56, height: diameter * 0.56)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !dragging {
                        let center = CGPoint(x: diameter / 2, y: diameter / 2)
                        let dx = value.startLocation.x - center.x, dy = value.startLocation.y - center.y
                        // A little more than the drawn cap: on a small knob the centre is hard to hit.
                        dragIsInner = (dx * dx + dy * dy).squareRoot() < diameter * 0.32
                        lastStep = 0
                        dragging = true
                    }
                    let travel = value.translation.width - value.translation.height
                    let step = Int(travel / clickDistance)
                    if step != lastStep {
                        click(step - lastStep)
                        lastStep = step
                    }
                }
                .onEnded { value in
                    let isTap = abs(value.translation.width) < 4 && abs(value.translation.height) < 4
                    if isTap {
                        if let onTap {
                            onTap()
                        } else {
                            click(value.startLocation.x < diameter / 2 ? -1 : 1)
                        }
                    }
                    lastStep = 0
                    dragging = false
                }
        )
        .overlay(alignment: .top) {
            if dragging {
                Text(dragIsInner ? "kHz" : "MHz")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(PanelTheme.checklistCyan))
                    .fixedSize()
                    .offset(y: -16)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            if !label.isEmpty { ControlLabel(text: label, size: 7).offset(y: 12) }
        }
        .opacity(dimmed ? 0.5 : 1)
        .disabled(!enabled)
        .sensoryFeedback(.selection, trigger: outerAngle + innerAngle)
        .accessibilityElement()
        .accessibilityLabel(label.isEmpty ? "Selector de frecuencia" : label)
        .accessibilityAdjustableAction { direction in
            click(direction == .increment ? 1 : -1)
        }
    }

    private func click(_ delta: Int) {
        guard delta != 0 else { return }
        if dragIsInner { innerAngle += Double(delta) * 15 } else { outerAngle += Double(delta) * 15 }
        onTurn(dragIsInner, delta)
    }
}

/// Pulsing ring around the control a checklist item points at.
struct LocateRing: View {
    let diameter: CGFloat

    var body: some View {
        Circle()
            .stroke(PanelTheme.checklistCyan, lineWidth: 3)
            .frame(width: diameter, height: diameter)
            .shadow(color: PanelTheme.checklistCyan.opacity(0.8), radius: 6)
            .phaseAnimator([false, true]) { ring, expanded in
                ring.scaleEffect(expanded ? 1.3 : 0.95).opacity(expanded ? 0.4 : 1)
            } animation: { _ in
                .easeInOut(duration: 0.55)
            }
            .allowsHitTesting(false)
    }
}

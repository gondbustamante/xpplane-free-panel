import SwiftUI

struct KorryLamp {
    let text: String
    let color: Color
    let lit: Bool
}

/// Square Airbus pushbutton with an upper and lower legend. Unlit legends are barely visible,
/// lit ones glow in their colour. Depresses while touched. When `guarded`, a hinged cover sits
/// over the button: one tap lifts it, the next tap presses, and it drops back after a few seconds.
struct KorryButtonView: View {
    let label: String
    let top: KorryLamp?
    let bottom: KorryLamp?
    var guarded = false
    let enabled: Bool
    var dimmed = false
    /// "cage" (black see-through frame) or "red" (solid hinged cover).
    var guardStyle = "cage"
    var sideLabel: String? = nil
    /// Inline: label above in a VStack (grid panels). Otherwise the label is an overlay and the
    /// view's frame is the button itself (absolute panels).
    var inline = true
    var size: CGFloat = 58
    var labelBelow = false
    let onPress: () -> Void

    @State private var guardOpen = false
    @State private var guardTimer: Task<Void, Never>?

    var body: some View {
        Group {
            if inline {
                VStack(spacing: 5) {
                    PanelLabel(text: label)
                    guardedButton
                }
            } else {
                guardedButton
                    .overlay(alignment: labelBelow ? .bottom : .top) {
                        if !label.isEmpty {
                            ControlLabel(text: label)
                                .offset(y: labelBelow ? PanelMetrics.labelGap + 4 : -PanelMetrics.labelGap - 4)
                        }
                    }
                    .overlay(alignment: .trailing) {
                        if let sideLabel {
                            VStack(spacing: -1) {
                                ForEach(Array(sideLabel.enumerated()), id: \.offset) { _, letter in
                                    Text(String(letter)).font(.system(size: 7, weight: .semibold)).foregroundStyle(PanelTheme.legend)
                                }
                            }
                            .offset(x: 8)
                        }
                    }
            }
        }
        .opacity(dimmed ? 0.5 : 1)
    }

    private var guardedButton: some View {
        ZStack(alignment: .top) {
            button
            if guarded {
                if guardStyle == "red" { redGuard } else { cageGuard }
            }
        }
        .frame(width: size, height: size)
    }

    private var button: some View {
        Button {
            onPress()
            if guarded { closeGuard() }
        } label: {
            VStack(spacing: 0) {
                half(top)
                Rectangle().fill(Color(white: 0.22)).frame(height: 1)
                half(bottom)
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 2)
                    .fill(PanelTheme.korryFace)
            )
            .padding(4)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [PanelTheme.bezel, Color(white: 0.24)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.8), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(KorryPressStyle())
        .disabled(!enabled)
    }

    /// Black see-through cage hinged on its top edge (EVAC COMMAND, DITCHING, RAM AIR, MAN START…).
    private var cageGuard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color(white: 0.10), lineWidth: 3)
                .padding(1.5)
            Rectangle().fill(Color(white: 0.10)).frame(width: 3)
            Rectangle().fill(Color(white: 0.10)).frame(height: 3)
            RoundedRectangle(cornerRadius: 3).fill(Color.black.opacity(0.18))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .modifier(GuardHinge(open: guardOpen))
        .allowsHitTesting(!guardOpen)
        .onTapGesture { openGuard() }
        .disabled(!enabled)
    }

    /// Solid red hinged cover (IDG, MAN ON, MASK MAN ON, DISCH, RAT MAN ON).
    private var redGuard: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3)
                .fill(LinearGradient(colors: [Color(red: 0.93, green: 0.22, blue: 0.18), Color(red: 0.72, green: 0.10, blue: 0.08)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.6), lineWidth: 1))
            RoundedRectangle(cornerRadius: 1).fill(Color.black).frame(width: size * 0.45, height: 3).padding(.top, 3)
            Rectangle().fill(Color.black.opacity(0.35)).frame(width: 1.5).padding(.vertical, 8)
        }
        .frame(width: size, height: size)
        .modifier(GuardHinge(open: guardOpen))
        .allowsHitTesting(!guardOpen)
        .onTapGesture { openGuard() }
        .disabled(!enabled)
    }

    private func openGuard() {
        guardOpen = true
        guardTimer?.cancel()
        guardTimer = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { guardOpen = false }
        }
    }

    private func closeGuard() {
        guardTimer?.cancel()
        guardTimer = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { guardOpen = false }
        }
    }

    @ViewBuilder
    private func half(_ lamp: KorryLamp?) -> some View {
        ZStack {
            Rectangle()
                .fill(lamp?.lit == true ? lamp!.color.opacity(0.22) : Color.clear)
            if let lamp {
                Text(lamp.text)
                    .font(.system(size: size * 0.17, weight: .heavy)).fontWidth(.condensed)
                    .foregroundStyle(lamp.lit ? lamp.color : PanelTheme.unlitLegend)
                    .shadow(color: lamp.lit ? lamp.color.opacity(1) : .clear, radius: 5)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 1.5)
                            .stroke(lamp.lit ? lamp.color.opacity(0.9) : PanelTheme.unlitLegend.opacity(0.7), lineWidth: 0.8)
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                // Unused half: the two tiny lamp dots visible on a blank Korry.
                HStack(spacing: size * 0.14) {
                    Circle().fill(Color(white: 0.30)).frame(width: size * 0.06, height: size * 0.06)
                    Circle().fill(Color(white: 0.30)).frame(width: size * 0.06, height: size * 0.06)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    HStack(spacing: 24) {
        KorryButtonView(label: "APU GEN",
                        top: KorryLamp(text: "FAULT", color: PanelTheme.lamp("amber"), lit: false),
                        bottom: KorryLamp(text: "OFF", color: PanelTheme.lamp("white"), lit: true),
                        enabled: true) {}
        KorryButtonView(label: "APU START",
                        top: KorryLamp(text: "AVAIL", color: PanelTheme.lamp("green"), lit: true),
                        bottom: KorryLamp(text: "ON", color: PanelTheme.lamp("blue"), lit: true),
                        enabled: true) {}
        KorryButtonView(label: "IDG 1",
                        top: KorryLamp(text: "FAULT", color: PanelTheme.lamp("amber"), lit: false),
                        bottom: nil,
                        guarded: true,
                        enabled: true, guardStyle: "red") {}
    }
    .padding(30)
    .background(PanelTheme.panelFace)
}

/// Lifts a guard about its top edge.
struct GuardHinge: ViewModifier {
    let open: Bool
    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(open ? 0.1 : 0.45), radius: 3, y: 2)
            .rotation3DEffect(.degrees(open ? -105 : 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.7)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: open)
    }
}

/// Sinks the button while touched. A `Button` (unlike a zero-distance drag) cooperates with the
/// surrounding scroll view: a tap presses, a swipe scrolls.
struct KorryPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .shadow(color: .black.opacity(configuration.isPressed ? 0.15 : 0.55),
                    radius: configuration.isPressed ? 1 : 3, y: configuration.isPressed ? 0.5 : 2.5)
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .offset(y: configuration.isPressed ? 1.5 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

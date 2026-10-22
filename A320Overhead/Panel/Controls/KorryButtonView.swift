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
    let onPress: () -> Void

    @State private var guardOpen = false
    @State private var guardTimer: Task<Void, Never>?

    private let size: CGFloat = 58

    var body: some View {
        VStack(spacing: 5) {
            PanelLabel(text: label)
            ZStack(alignment: .top) {
                button
                if guarded { guardCover }
            }
            .frame(width: size, height: size)
        }
        .opacity(dimmed ? 0.5 : 1)
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

    /// Clear plastic guard hinged on its top edge, with the red and white diagonal stripes of the
    /// real switch guards. Translucent so the button legend stays readable underneath.
    private var guardCover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.18))
            ForEach(0..<5, id: \.self) { index in
                Rectangle()
                    .fill(index % 2 == 0 ? Color(red: 0.90, green: 0.12, blue: 0.10).opacity(0.85)
                                         : Color.white.opacity(0.75))
                    .frame(width: 9, height: size * 2)
                    .offset(x: CGFloat(index - 2) * 18)
                    .rotationEffect(.degrees(-45))
            }
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.7), lineWidth: 1.2)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(guardOpen ? 0.1 : 0.45), radius: 3, y: 2)
        .rotation3DEffect(.degrees(guardOpen ? -105 : 0), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.7)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: guardOpen)
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
                .fill(lamp?.lit == true ? lamp!.color.opacity(0.28) : Color.clear)
            if let lamp {
                Text(lamp.text)
                    .font(.system(size: 10.5, weight: .heavy))
                    .foregroundStyle(lamp.lit ? lamp.color : PanelTheme.unlitLegend)
                    .shadow(color: lamp.lit ? lamp.color.opacity(1) : .clear, radius: 5)
                    .shadow(color: lamp.lit ? lamp.color.opacity(0.6) : .clear, radius: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
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
                        enabled: true) {}
    }
    .padding(30)
    .background(PanelTheme.panelFace)
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

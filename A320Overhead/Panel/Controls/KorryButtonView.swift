import SwiftUI

struct KorryLamp {
    let text: String
    let color: Color
    let lit: Bool
}

/// Square Airbus pushbutton with an upper and lower legend. Unlit legends are barely visible,
/// lit ones glow in their colour. Depresses while touched.
struct KorryButtonView: View {
    let label: String
    let top: KorryLamp?
    let bottom: KorryLamp?
    let enabled: Bool
    let onPress: () -> Void

    @State private var pressed = false

    var body: some View {
        VStack(spacing: 5) {
            PanelLabel(text: label)
            button
        }
        .opacity(enabled ? 1 : 0.45)
    }

    private var button: some View {
        VStack(spacing: 2) {
            half(top)
            half(bottom)
        }
        .padding(4)
        .frame(width: 58, height: 58)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(white: 0.16), Color(white: 0.08)],
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
    }

    @ViewBuilder
    private func half(_ lamp: KorryLamp?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(lamp?.lit == true ? lamp!.color.opacity(0.22) : Color.black.opacity(0.35))
            if let lamp {
                Text(lamp.text)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(lamp.lit ? lamp.color : PanelTheme.unlitLegend)
                    .shadow(color: lamp.lit ? lamp.color.opacity(0.9) : .clear, radius: 4)
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
    }
    .padding(30)
    .background(PanelTheme.panelFace)
}

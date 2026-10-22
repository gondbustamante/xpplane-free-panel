import SwiftUI

/// 2.5D lever switch. The knob travels up/down from a central pivot and shrinks slightly at the
/// extremes, which reads as a lever tilting toward and away from the viewer.
/// Tap the upper half to move up, lower half to move down, or flick vertically.
struct ToggleSwitchView: View {
    let label: String
    /// Position names ordered bottom → top.
    let positions: [String]
    let position: Int
    let enabled: Bool
    var dimmed = false
    let onMove: (Int) -> Void

    private let bodyWidth: CGFloat = 42
    private let bodyHeight: CGFloat = 70
    private let throwDistance: CGFloat = 21

    private var count: Int { max(positions.count, 2) }

    /// -1 at the bottom position, +1 at the top.
    private var tilt: CGFloat {
        let normalized = CGFloat(min(max(position, 0), count - 1)) / CGFloat(count - 1)
        return normalized * 2 - 1
    }

    var body: some View {
        VStack(spacing: 3) {
            PanelLabel(text: label)
            PanelLabel(text: positions.last ?? "", small: true)
            HStack(spacing: 5) {
                if count == 3 { Color.clear.frame(width: 30, height: 1) }
                lever
                if count == 3 {
                    PanelLabel(text: positions[1], small: true).frame(width: 30, alignment: .leading)
                }
            }
            PanelLabel(text: positions.first ?? "", small: true)
        }
        .opacity(dimmed ? 0.5 : 1)
    }

    private var lever: some View {
        let dy = -tilt * throwDistance
        return ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(LinearGradient(colors: [Color(white: 0.21), Color(white: 0.10)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.75), lineWidth: 1))
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)

            Circle()
                .fill(LinearGradient(colors: [PanelTheme.bezel, Color(white: 0.20)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: 21, height: 21)
            Circle()
                .fill(Color.black)
                .frame(width: 15, height: 15)

            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.42), Color(white: 0.88), Color(white: 0.38)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: 10, height: abs(dy) + 10)
                .offset(y: dy / 2)

            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.97), Color(white: 0.55)],
                                     center: UnitPoint(x: 0.35, y: 0.30), startRadius: 1, endRadius: 16))
                .frame(width: 25, height: 25)
                .scaleEffect(1 - 0.12 * abs(tilt))
                .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 2)
                .offset(y: dy)
        }
        .frame(width: bodyWidth, height: bodyHeight)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.18, dampingFraction: 0.65), value: position)
        .onTapGesture { location in
            onMove(location.y < bodyHeight / 2 ? 1 : -1)
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -12 {
                        onMove(1)
                    } else if value.translation.height > 12 {
                        onMove(-1)
                    }
                }
        )
        .disabled(!enabled)
    }
}

#Preview {
    HStack(spacing: 24) {
        ToggleSwitchView(label: "BEACON", positions: ["OFF", "ON"], position: 1, enabled: true) { _ in }
        ToggleSwitchView(label: "STROBE", positions: ["OFF", "AUTO", "ON"], position: 1, enabled: true) { _ in }
        ToggleSwitchView(label: "NOSE", positions: ["OFF", "TAXI", "T.O"], position: 0, enabled: false) { _ in }
    }
    .padding(30)
    .background(PanelTheme.panelFace)
}

import SwiftUI

/// Rotary selector with N detents. Positions run left → right; the pointer sweeps 120°.
/// Tap the left/right half or drag horizontally to step.
struct RotarySelectorView: View {
    let label: String
    let positions: [String]
    let position: Int
    let enabled: Bool
    let onMove: (Int) -> Void

    private let sweep: Double = 120
    private var count: Int { max(positions.count, 2) }

    private func angle(for index: Int) -> Double {
        -sweep / 2 + sweep * Double(index) / Double(count - 1)
    }

    var body: some View {
        VStack(spacing: 4) {
            PanelLabel(text: label)
            HStack(spacing: 6) {
                ForEach(positions.indices, id: \.self) { index in
                    PanelLabel(text: positions[index], small: true)
                        .opacity(index == position ? 1 : 0.55)
                }
            }
            knob
        }
        .opacity(enabled ? 1 : 0.45)
    }

    private var knob: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                Rectangle()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 2, height: 6)
                    .offset(y: -33)
                    .rotationEffect(.degrees(angle(for: index)))
            }
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.34), Color(white: 0.10)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 2, endRadius: 28))
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(Color.black.opacity(0.75), lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
            Capsule()
                .fill(Color.white)
                .frame(width: 4, height: 18)
                .offset(y: -15)
                .rotationEffect(.degrees(angle(for: min(max(position, 0), count - 1))))
        }
        .frame(width: 74, height: 74)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: position)
        .onTapGesture { location in
            onMove(location.x < 37 ? -1 : 1)
        }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.width > 12 {
                        onMove(1)
                    } else if value.translation.width < -12 {
                        onMove(-1)
                    }
                }
        )
        .disabled(!enabled)
    }
}

#Preview {
    HStack(spacing: 24) {
        RotarySelectorView(label: "IR 1", positions: ["OFF", "NAV", "ATT"], position: 1, enabled: true) { _ in }
        RotarySelectorView(label: "X BLEED", positions: ["SHUT", "AUTO", "OPEN"], position: 0, enabled: false) { _ in }
    }
    .padding(30)
    .background(PanelTheme.panelFace)
}

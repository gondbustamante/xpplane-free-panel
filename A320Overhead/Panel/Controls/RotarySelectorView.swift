import SwiftUI

/// Rotary selector with N detents. Positions run left → right; the pointer sweeps 120°.
/// Tap the left/right half or drag horizontally to step.
struct RotarySelectorView: View {
    let label: String
    let positions: [String]
    let position: Int
    let enabled: Bool
    var dimmed = false
    var inline = true
    var diameter: CGFloat = 52
    var labelBelow = false
    let onMove: (Int) -> Void

    private let sweep: Double = 120
    private var count: Int { max(positions.count, 2) }

    private func angle(for index: Int) -> Double {
        -sweep / 2 + sweep * Double(index) / Double(count - 1)
    }

    var body: some View {
        if inline {
            inlineBody
        } else {
            absoluteBody
        }
    }

    /// Light grey knob with a bar handle; legends sit around the arc, as on the aircraft.
    private var absoluteBody: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { index in
                Rectangle().fill(Color.white.opacity(0.9)).frame(width: 1.5, height: 5)
                    .offset(y: -diameter * 0.62).rotationEffect(.degrees(angle(for: index)))
            }
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.92), Color(white: 0.60)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 1, endRadius: diameter * 0.6))
                .frame(width: diameter, height: diameter)
                .overlay(Circle().stroke(Color.black.opacity(0.6), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.55), radius: 3, y: 2)
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(colors: [Color(white: 0.85), Color(white: 0.55)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: diameter * 0.26, height: diameter * 0.86)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.black.opacity(0.35), lineWidth: 0.6))
                Capsule().fill(Color(white: 0.2)).frame(width: 2, height: diameter * 0.36).offset(y: -diameter * 0.22)
            }
            .rotationEffect(.degrees(angle(for: min(max(position, 0), count - 1))))
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: position)
        .onTapGesture { location in onMove(location.x < diameter / 2 ? -1 : 1) }
        .overlay(alignment: labelBelow ? .bottom : .top) {
            if !label.isEmpty {
                ControlLabel(text: label).offset(y: labelBelow ? diameter * 0.22 + 10 : -diameter * 0.32 - 12)
            }
        }
        .overlay {
            ForEach(positions.indices, id: \.self) { index in
                let radians = (angle(for: index) - 90) * .pi / 180
                ControlLabel(text: positions[index], size: 7)
                    .opacity(index == position ? 1 : 0.8)
                    .offset(x: CGFloat(cos(radians)) * diameter * 0.82, y: CGFloat(sin(radians)) * diameter * 0.82)
            }
        }
        .opacity(dimmed ? 0.5 : 1)
        .disabled(!enabled)
    }

    private var inlineBody: some View {
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
        .opacity(dimmed ? 0.5 : 1)
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
                .fill(RadialGradient(colors: [Color(white: 0.30), Color(white: 0.08)],
                                     center: UnitPoint(x: 0.4, y: 0.35), startRadius: 2, endRadius: 28))
                .frame(width: 52, height: 52)
                .overlay(Circle().stroke(Color.black.opacity(0.8), lineWidth: 1))
                .shadow(color: .black.opacity(0.6), radius: 3, y: 2)
            // Bar handle with a white pointer line, as on the ADIRS and X BLEED selectors.
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.10)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: 14, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.7), lineWidth: 0.8))
                Capsule()
                    .fill(Color.white)
                    .frame(width: 3, height: 20)
                    .offset(y: -11)
            }
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

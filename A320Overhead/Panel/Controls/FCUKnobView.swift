import SwiftUI

/// 2.5D FCU selector knob. Drag horizontally (or around the knob) to turn it one click per
/// `clickDistance` points; the ring rotates with you. Flanked by − / + buttons that repeat while
/// held, and PUSH / PULL buttons underneath, because on the real unit pushing the knob means
/// "managed" and pulling it means "selected".
struct FCUKnobView: View {
    let enabled: Bool
    let hasPush: Bool
    let hasPull: Bool
    let onTurn: (Int) -> Void
    let onPush: () -> Void
    let onPull: () -> Void

    @State private var angle: Double = 0
    @State private var dragAccumulator: CGFloat = 0
    @State private var lastTranslation: CGFloat = 0

    private let diameter: CGFloat = 64
    private let clickDistance: CGFloat = 14
    private let degreesPerClick: Double = 18

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                RepeatButton(systemImage: "minus", enabled: enabled) { onTurn(-1) }
                knob
                RepeatButton(systemImage: "plus", enabled: enabled) { onTurn(1) }
            }
            HStack(spacing: 8) {
                FCUSmallButton(title: "PUSH", enabled: enabled && hasPush, action: onPush)
                FCUSmallButton(title: "PULL", enabled: enabled && hasPull, action: onPull)
            }
        }
        .opacity(enabled ? 1 : 0.45)
    }

    private var knob: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: diameter + 8, height: diameter + 8)
                .blur(radius: 3)
                .offset(y: 3)
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.34), Color(white: 0.12)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: diameter, height: diameter)
                .overlay(Circle().stroke(Color.black.opacity(0.8), lineWidth: 1))
            // Knurled ring: short radial ticks that spin with the knob.
            ZStack {
                ForEach(0..<24, id: \.self) { tick in
                    Capsule()
                        .fill(Color(white: tick % 2 == 0 ? 0.55 : 0.40))
                        .frame(width: 2, height: 7)
                        .offset(y: -diameter / 2 + 6)
                        .rotationEffect(.degrees(Double(tick) * 15))
                }
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 3, height: 14)
                    .offset(y: -diameter / 2 + 14)
            }
            .rotationEffect(.degrees(angle))
            .animation(.easeOut(duration: 0.08), value: angle)
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.30), Color(white: 0.16)],
                                     center: UnitPoint(x: 0.4, y: 0.3), startRadius: 1, endRadius: 20))
                .frame(width: diameter * 0.55, height: diameter * 0.55)
        }
        .frame(width: diameter + 8, height: diameter + 8)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let translation = value.translation.width - value.translation.height
                    dragAccumulator += translation - lastTranslation
                    lastTranslation = translation
                    while dragAccumulator >= clickDistance {
                        dragAccumulator -= clickDistance
                        angle += degreesPerClick
                        onTurn(1)
                    }
                    while dragAccumulator <= -clickDistance {
                        dragAccumulator += clickDistance
                        angle -= degreesPerClick
                        onTurn(-1)
                    }
                }
                .onEnded { _ in
                    dragAccumulator = 0
                    lastTranslation = 0
                }
        )
        .disabled(!enabled)
    }
}

/// Round − / + button that fires once on tap and keeps firing while held.
struct RepeatButton: View {
    let systemImage: String
    let enabled: Bool
    let action: () -> Void

    @State private var pressed = false
    @State private var repeater: Task<Void, Never>?
    @State private var firedWhileHeld = false

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(Circle().fill(pressed ? Color(white: 0.30) : Color(white: 0.18)))
            .overlay(Circle().stroke(Color(white: 0.45), lineWidth: 1))
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        firedWhileHeld = false
                        repeater = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            while !Task.isCancelled {
                                firedWhileHeld = true
                                action()
                                try? await Task.sleep(for: .milliseconds(110))
                            }
                        }
                    }
                    .onEnded { _ in
                        repeater?.cancel()
                        repeater = nil
                        pressed = false
                        if !firedWhileHeld { action() }
                    }
            )
            .disabled(!enabled)
    }
}

/// Flat rectangular legend button used for PUSH / PULL.
struct FCUSmallButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(.white)
                .frame(width: 48, height: 24)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.17)))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(white: 0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

#Preview {
    FCUKnobView(enabled: true, hasPush: true, hasPull: true, onTurn: { _ in }, onPush: {}, onPull: {})
        .padding(30)
        .background(PanelTheme.panelFace)
}

import SwiftUI

/// Airbus-ish palette. The overhead face is a warm dark grey; legends are white;
/// annunciators use the standard amber / green / white / blue.
enum PanelTheme {
    static let cockpitBackground = Color(red: 0.07, green: 0.08, blue: 0.10)
    /// Airbus cockpit grey: a dark, slightly blue grey.
    static let panelFace = Color(red: 0.33, green: 0.37, blue: 0.43)
    static let panelFaceHighlight = Color(red: 0.38, green: 0.42, blue: 0.48)
    static let panelEdge = Color(red: 0.16, green: 0.17, blue: 0.19)
    /// Dark gap between plates.
    static let panelGap = Color(red: 0.13, green: 0.14, blue: 0.17)
    /// Synoptic lines on HYD, FUEL, ELEC and AIR COND.
    static let synoptic = Color(red: 0.36, green: 0.93, blue: 0.40)
    static let fcuDigitsColor = Color(red: 1.0, green: 0.66, blue: 0.18)
    static let bezel = Color(red: 0.42, green: 0.44, blue: 0.46)
    static let korryFace = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let legend = Color.white
    static let unlitLegend = Color(white: 0.42)
    static let verificationBadge = Color(red: 1.0, green: 0.62, blue: 0.0)
    /// LCD digits of the FCU windows (warm amber, like the ToLiss unit).
    static let fcuDigits = Color(red: 1.0, green: 0.66, blue: 0.18)

    static func lamp(_ name: String) -> Color {
        switch name.lowercased() {
        case "amber": return Color(red: 1.00, green: 0.69, blue: 0.00)
        case "green": return Color(red: 0.25, green: 0.95, blue: 0.45)
        case "blue": return Color(red: 0.45, green: 0.72, blue: 1.00)
        case "red": return Color(red: 1.00, green: 0.22, blue: 0.15)
        default: return Color.white
        }
    }
}

/// Slotted screw head, as on the corners of every Airbus subpanel.
struct ScrewView: View {
    var size: CGFloat = 7

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.62), Color(white: 0.28)],
                                     center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: size * 0.7))
            Rectangle()
                .fill(Color.black.opacity(0.75))
                .frame(width: size * 0.8, height: 1.2)
                .rotationEffect(.degrees(28))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.6), radius: 0.8, y: 0.6)
    }
}

// MARK: - Integral lighting (backlit legends)

private struct BacklightKey: EnvironmentKey {
    static let defaultValue: Double = 0.75
}

extension EnvironmentValues {
    /// 0…1 level of the integral lighting of the panel being drawn. Legends, key captions and
    /// painted lines glow with it, as they do in the aircraft. Set per panel group by the canvas.
    var backlight: Double {
        get { self[BacklightKey.self] }
        set { self[BacklightKey.self] = newValue }
    }
}

extension PanelTheme {
    /// Warm white of Airbus integral lighting.
    static let backlightGlow = Color(red: 1.00, green: 0.93, blue: 0.80)

    /// Legend colour: painted white when unlit, warming as the integral lighting comes up.
    static func legend(_ level: Double) -> Color {
        let l = min(max(level, 0), 1)
        return Color(red: 0.90 + 0.10 * l, green: 0.90 + 0.06 * l, blue: 0.90 - 0.02 * l)
    }
}

/// Glow of a backlit legend or painted line, following `\.backlight`.
struct Backlit: ViewModifier {
    @Environment(\.backlight) private var level

    func body(content: Content) -> some View {
        content.shadow(color: PanelTheme.backlightGlow.opacity(0.85 * min(max(level, 0), 1)),
                       radius: 0.6 + 2.0 * level)
    }
}

extension View {
    /// Lights this legend with the panel's integral lighting.
    func backlit() -> some View { modifier(Backlit()) }
}

struct PanelLabel: View {
    let text: String
    var small = false
    @Environment(\.backlight) private var level

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: small ? 10 : 11.5, weight: .semibold, design: .default))
            .tracking(0.4)
            .foregroundStyle(PanelTheme.legend(level))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .backlit()
    }
}

import SwiftUI

/// Airbus-ish palette. The overhead face is a warm dark grey; legends are white;
/// annunciators use the standard amber / green / white / blue.
enum PanelTheme {
    static let cockpitBackground = Color(red: 0.09, green: 0.10, blue: 0.11)
    static let panelFace = Color(red: 0.27, green: 0.28, blue: 0.29)
    static let panelFaceHighlight = Color(red: 0.33, green: 0.34, blue: 0.35)
    static let legend = Color.white
    static let unlitLegend = Color(white: 0.30)
    static let verificationBadge = Color(red: 1.0, green: 0.62, blue: 0.0)
    /// LCD digits of the FCU windows (warm amber, like the ToLiss unit).
    static let fcuDigits = Color(red: 1.0, green: 0.66, blue: 0.18)

    static func lamp(_ name: String) -> Color {
        switch name.lowercased() {
        case "amber": return Color(red: 1.00, green: 0.69, blue: 0.00)
        case "green": return Color(red: 0.25, green: 0.95, blue: 0.45)
        case "blue": return Color(red: 0.45, green: 0.72, blue: 1.00)
        default: return Color.white
        }
    }
}

struct PanelLabel: View {
    let text: String
    var small = false

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: small ? 10 : 11.5, weight: .semibold, design: .default))
            .tracking(0.4)
            .foregroundStyle(PanelTheme.legend)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

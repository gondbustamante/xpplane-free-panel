import SwiftUI
import XPlaneKit

extension DemoTiming {
    var title: String {
        switch self {
        case .realistic: return "Realista"
        case .fast: return "Rápido"
        case .instant: return "Instantáneo"
        }
    }

    var explanation: String {
        switch self {
        case .realistic:
            return "Como en el avión: la toma de aire del APU tarda unos 5 s en abrirse, el APU unos 50 s en estar AVAIL, las IRS 10 min en alinearse y cada motor unos 45 s en arrancar."
        case .fast:
            return "Los mismos procesos a un quinto de su duración: APU en 10 s, IRS en 2 min, motor en 9 s. Para practicar el orden sin esperar."
        case .instant:
            return "Todo termina al momento. Las dependencias se mantienen: sin energía no arranca el APU y sin aire de sangrado no arranca el motor."
        }
    }
}

/// Strip under the connection bar in demo mode: an ECAM-memo style summary of the systems
/// (power, APU, IRS, engines) and the timing, so waiting for the APU or the IRS is visible.
struct DemoSystemsStrip: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        @Bindable var model = model
        if let status = model.demoSystems {
            HStack(spacing: 10) {
                Image(systemName: icon(status.power))
                    .foregroundStyle(status.power == .none ? PanelTheme.checklistAmber : PanelTheme.checklistGreen)
                    .accessibilityLabel(powerLabel(status.power))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(status.lines, id: \.self) { line in
                            Text(line.text)
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(colour(line.color))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(colour(line.color).opacity(0.12)))
                                .lineLimit(1)
                        }
                    }
                }
                Menu {
                    Picker("Tiempos", selection: $model.demoTiming) {
                        ForEach(DemoTiming.allCases) { timing in
                            Text(timing.title).tag(timing)
                        }
                    }
                    Divider()
                    Button("Avión en Cold & Dark", systemImage: "arrow.counterclockwise", role: .destructive) {
                        // A reset under an exercise would read as steps undone.
                        if model.isExerciseRunning { model.abandonExercise() }
                        Task { await model.resetDemoAircraft() }
                    }
                } label: {
                    Label(model.demoTiming.title, systemImage: model.demoTiming == .instant ? "bolt.fill" : "timer")
                        .font(.caption)
                }
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(Color.black.opacity(0.35))
        }
    }

    private func icon(_ power: DemoSystemsStatus.Power) -> String {
        switch power {
        case .none: return "bolt.slash.fill"
        case .battery: return "battery.75percent"
        case .ac: return "bolt.fill"
        }
    }

    private func powerLabel(_ power: DemoSystemsStatus.Power) -> String {
        switch power {
        case .none: return "Sin energía"
        case .battery: return "Solo baterías"
        case .ac: return "Corriente alterna"
        }
    }

    private func colour(_ name: String) -> Color {
        switch name {
        case "green": return PanelTheme.checklistGreen
        case "amber": return PanelTheme.checklistAmber
        case "cyan": return PanelTheme.checklistCyan
        default: return .white
        }
    }
}

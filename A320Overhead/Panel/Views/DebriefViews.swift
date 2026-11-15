import Charts
import SwiftUI
import XPlaneKit

/// Post-flight report: score, the flight profile with its events marked, the final approach and
/// the list of events, as a flight data analyst would go through them.
struct DebriefSheet: View {
    let debrief: FlightDebrief
    @Environment(\.dismiss) private var dismiss

    private var minutes: Double { debrief.end.timeIntervalSince(debrief.start) / 60 }

    /// The last ten minutes before the touchdown, where most events are.
    private var finalApproach: [FlightSample] {
        guard let touchdown = lastTouchdown else { return [] }
        return debrief.samples.filter { $0.time >= touchdown - 600 && $0.time <= touchdown + 30 }
    }

    /// Time of the last transition from air to ground.
    private var lastTouchdown: TimeInterval? {
        let samples = debrief.samples
        guard let index = samples.indices.dropFirst().last(where: { !samples[$0 - 1].onGround && samples[$0].onGround }) else {
            return nil
        }
        return samples[index].time
    }

    var body: some View {
        NavigationStack {
            List {
                Section { summary }
                Section("Perfil del vuelo") {
                    profileChart.frame(height: 200)
                    speedChart.frame(height: 150)
                }
                if !finalApproach.isEmpty {
                    Section {
                        approachChart.frame(height: 170)
                    } header: {
                        Text("Aproximación final")
                    } footer: {
                        Text("Régimen de descenso en los últimos diez minutos. La franja marca el límite de 1000 ft/min por debajo de 1000 ft.")
                    }
                }
                Section {
                    if debrief.events.isEmpty {
                        Label("Sin eventos: un vuelo limpio.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(PanelTheme.checklistGreen)
                    }
                    ForEach(debrief.events) { event in
                        EventRow(event: event)
                    }
                } header: {
                    Text("Eventos (\(debrief.events.count))")
                } footer: {
                    Text("Umbrales habituales de monitorización de datos de vuelo (FDM) para el A320. Cada evento resta puntos según su gravedad: leve 3, media 8, alta 20.")
                }
            }
            .navigationTitle(debrief.title.isEmpty ? "Informe del vuelo" : debrief.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: DebriefText.summary(debrief)) {
                        Label("Compartir", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 20) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: Double(debrief.score) / 100)
                    .stroke(scoreColour, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(debrief.score)").font(.system(size: 30, weight: .bold).monospacedDigit())
                    Text("/100").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 4) {
                Text(debrief.grade).font(.title3.weight(.semibold)).foregroundStyle(scoreColour)
                Text(debrief.start.formatted(date: .abbreviated, time: .shortened)).font(.footnote)
                Text("Duración \(Int(minutes.rounded())) min").font(.footnote).foregroundStyle(.secondary)
                if let rate = debrief.landingRate {
                    Text("Toma: \(rate) ft/min" + (debrief.landingG.map { String(format: " · %.2f g", $0) } ?? ""))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var scoreColour: Color {
        switch debrief.score {
        case 90...: return PanelTheme.checklistGreen
        case 75..<90: return PanelTheme.checklistCyan
        case 50..<75: return PanelTheme.checklistAmber
        default: return .red
        }
    }

    private var profileChart: some View {
        Chart {
            ForEach(debrief.samples, id: \.time) { sample in
                AreaMark(x: .value("Minuto", sample.time / 60), y: .value("Altitud (ft)", sample.altitude))
                    .foregroundStyle(PanelTheme.checklistCyan.opacity(0.18))
                LineMark(x: .value("Minuto", sample.time / 60), y: .value("Altitud (ft)", sample.altitude))
                    .foregroundStyle(PanelTheme.checklistCyan)
            }
            ForEach(debrief.events) { event in
                RuleMark(x: .value("Minuto", event.time / 60))
                    .foregroundStyle(EventRow.colour(event.severity).opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXAxisLabel("min")
        .chartYAxisLabel("ft")
    }

    private var speedChart: some View {
        Chart(debrief.samples, id: \.time) { sample in
            LineMark(x: .value("Minuto", sample.time / 60), y: .value("IAS (kt)", sample.ias))
                .foregroundStyle(PanelTheme.checklistGreen)
        }
        .chartXAxisLabel("min")
        .chartYAxisLabel("kt")
    }

    private var approachChart: some View {
        Chart {
            RectangleMark(yStart: .value("Límite", -1000), yEnd: .value("Límite", -3000))
                .foregroundStyle(Color.red.opacity(0.10))
            ForEach(finalApproach, id: \.time) { sample in
                LineMark(x: .value("Minuto", sample.time / 60), y: .value("V/S (ft/min)", sample.verticalSpeed))
                    .foregroundStyle(PanelTheme.checklistAmber)
            }
        }
        .chartYScale(domain: -2000...500)
        .chartXAxisLabel("min")
        .chartYAxisLabel("ft/min")
    }
}

private struct EventRow: View {
    let event: FlightEvent

    static func colour(_ severity: FlightEvent.Severity) -> Color {
        switch severity {
        case .low: return PanelTheme.checklistCyan
        case .medium: return PanelTheme.checklistAmber
        case .high: return .red
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.severity == .high ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(Self.colour(event.severity))
            VStack(alignment: .leading, spacing: 2) {
                Text(event.kind.title).font(.subheadline.weight(.semibold))
                Text(event.detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text("min \(Int(event.time / 60))").font(.caption.monospacedDigit())
                Text(event.severity.title).font(.caption2).foregroundStyle(Self.colour(event.severity))
            }
        }
    }
}

enum DebriefText {
    static func summary(_ debrief: FlightDebrief) -> String {
        var lines = ["Informe del vuelo \(debrief.title)",
                     "\(debrief.start.formatted(date: .abbreviated, time: .shortened)) · \(debrief.score)/100 (\(debrief.grade))"]
        if let rate = debrief.landingRate { lines.append("Toma: \(rate) ft/min") }
        lines.append(debrief.events.isEmpty ? "Sin eventos." : "Eventos:")
        for event in debrief.events {
            lines.append("- min \(Int(event.time / 60)) · \(event.kind.title) (\(event.severity.title)): \(event.detail)")
        }
        return lines.joined(separator: "\n")
    }
}

/// Past reports in the sidebar's flight tab.
struct DebriefList: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        if model.debriefIndex.isEmpty {
            Text("Con X-Plane, cada vuelo se graba desde el primer movimiento hasta el puesto y deja aquí su informe.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        ForEach(model.debriefIndex.prefix(10)) { entry in
            Button {
                model.showDebrief(entry.id)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title.isEmpty ? "Vuelo" : entry.title).lineLimit(1)
                        Text(entry.end.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(entry.score)")
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(entry.score >= 90 ? PanelTheme.checklistGreen : entry.score >= 75 ? PanelTheme.checklistCyan : PanelTheme.checklistAmber)
                }
            }
            .swipeActions {
                Button("Borrar", role: .destructive) { model.deleteDebrief(entry.id) }
            }
        }
    }
}

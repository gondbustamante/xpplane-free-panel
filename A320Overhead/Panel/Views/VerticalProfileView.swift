import Charts
import SwiftUI
import XPlaneKit

/// Vertical display under the map, after the A350's VD: the OFP profile (magenta), what has been
/// flown (green), where the present vertical speed takes the aircraft and where it levels off at
/// the altitude the autopilot is flying to (white, dashed), the FCU altitude (cyan), the FMS
/// target when a constraint holds it elsewhere (magenta), the FMS descent path as flown, the 3:1
/// path into the destination, TOC/TOD and the airports. "Adelante" follows the aircraft; "Ruta"
/// shows it all.
struct VerticalProfileView: View {
    var large = false
    @Environment(PanelModel.self) private var model
    @State private var wholeRoute = false

    /// NM shown behind and ahead of the aircraft when following it.
    private let behind = 15.0
    private let ahead = 80.0

    private var selectedAltitude: Double? {
        model.rawValues["sim/cockpit/autopilot/altitude"]?.doubleValue.flatMap { $0 > 0 ? $0 : nil }
    }

    var body: some View {
        if let profile = model.verticalProfile, profile.planned.count > 1 {
            content(profile)
        } else {
            Text("Carga un OFP de SimBrief para ver el perfil vertical.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.85))
        }
    }

    private func content(_ profile: VerticalProfile) -> some View {
        let data = model.liveFlight
        let along = data.flatMap { profile.distanceAlong(latitude: $0.latitude, longitude: $0.longitude) }
        let projection = data.flatMap { data in
            // Level off where the autopilot will: a constraint before the FCU altitude counts.
            along.map { VerticalProfile.projection(distance: $0, altitude: data.altitude, groundspeed: data.groundspeed,
                                                   verticalSpeed: data.verticalSpeed,
                                                   selectedAltitude: model.liveFMS.targetAltitude ?? selectedAltitude,
                                                   ahead: ahead) }
        } ?? []
        let start = profile.planned.first?.distance ?? 0
        let domain: ClosedRange<Double> = {
            if !wholeRoute, let along { return (along - behind)...(along + ahead) }
            return start...max(profile.destinationDistance, start + 1)
        }()
        let visibleTop = (profile.planned + model.flownProfile + projection)
            .filter { domain.contains($0.distance) }
            .map(\.altitude)
            .max() ?? 10_000
        let top = max(visibleTop, data?.altitude ?? 0, selectedAltitude ?? 0) + 3000

        return VStack(alignment: .leading, spacing: 4) {
            header(profile, along: along, projection: projection)
            chart(profile, along: along, projection: projection, domain: domain, top: top)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.88))
    }

    private func header(_ profile: VerticalProfile, along: Double?, projection: [VerticalProfile.Point]) -> some View {
        HStack(spacing: 12) {
            Text("PERFIL VERTICAL")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            if let data = model.liveFlight, let along, let planned = profile.plannedAltitude(at: along) {
                let deviation = data.altitude - planned
                Text(abs(deviation) < 300 ? "En el perfil" : "\(deviation > 0 ? "+" : "−")\(Int(abs(deviation)).formatted()) ft \(deviation > 0 ? "sobre" : "bajo") el plan")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(abs(deviation) < 1000 ? PanelTheme.checklistGreen : PanelTheme.checklistAmber)
            }
            if projection.count == 3, let along {
                Text("Nivela en \(Int((projection[1].distance - along).rounded())) NM")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.8))
            }
            // VDEV as on the PFD: above (+) or below the managed descent path.
            if let data = model.liveFlight, let path = model.liveFMS.descentPathAltitude, !data.onGround {
                let vdev = data.altitude - path
                Text("VDEV \(vdev >= 0 ? "+" : "−")\(Int(abs(vdev)).formatted())")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 1.0))
            }
            if let distance = model.liveFMS.distanceToDestination {
                Text("FMS \(Int(distance.rounded())) NM")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            Picker("Alcance", selection: $wholeRoute) {
                Text("Adelante").tag(false)
                Text("Ruta").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .controlSize(.mini)
            .disabled(model.liveFlight == nil)
        }
    }

    private func chart(_ profile: VerticalProfile, along: Double?, projection: [VerticalProfile.Point],
                       domain: ClosedRange<Double>, top: Double) -> some View {
        let descent = profile.descentPath(ceiling: profile.planned.map(\.altitude).max() ?? 10_000)
        return Chart {
            // SIGMETs on the route at their levels, behind everything else.
            ForEach(model.routeHazards) { hazard in
                RectangleMark(xStart: .value("NM", hazard.entry), xEnd: .value("NM", max(hazard.exit, hazard.entry + 2)),
                              yStart: .value("ft", Double(hazard.sigmet.base ?? 0)),
                              yEnd: .value("ft", min(top, Double(hazard.sigmet.top ?? Int(top)))))
                    .foregroundStyle(hazard.sigmet.hazard.colour.opacity(0.22))
                    .annotation(position: .overlay, alignment: .top) {
                        Text(hazard.sigmet.hazard.title)
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(hazard.sigmet.hazard.colour)
                    }
            }
            ForEach(Array(descent.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("NM", point.distance), y: .value("ft", point.altitude), series: .value("Serie", "3:1"))
                    .foregroundStyle(Color.gray.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
            }
            ForEach(Array(profile.planned.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("NM", point.distance), y: .value("ft", point.altitude), series: .value("Serie", "Plan"))
                    .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 1.0))
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(Array(model.flownProfile.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("NM", point.distance), y: .value("ft", point.altitude), series: .value("Serie", "Volado"))
                    .foregroundStyle(PanelTheme.checklistGreen)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
            }
            ForEach(Array(model.fmsDescentProfile.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("NM", point.distance), y: .value("ft", point.altitude), series: .value("Serie", "Senda FMS"))
                    .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 1.0).opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [1, 3]))
            }
            ForEach(Array(projection.enumerated()), id: \.offset) { _, point in
                LineMark(x: .value("NM", point.distance), y: .value("ft", point.altitude), series: .value("Serie", "Proyección"))
                    .foregroundStyle(.white)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            }
            if let selected = selectedAltitude {
                RuleMark(y: .value("FCU", selected))
                    .foregroundStyle(PanelTheme.checklistCyan.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("FCU \(Int(selected).formatted())")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(PanelTheme.checklistCyan)
                    }
            }
            // The FMS target when a constraint holds the aircraft short of the FCU altitude.
            if let target = model.liveFMS.targetAltitude, abs(target - (selectedAltitude ?? -1000)) > 50 {
                RuleMark(y: .value("FMS", target))
                    .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 1.0).opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text("FMS \(Int(target).formatted())")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 1.0))
                    }
            }
            ForEach(Array(profile.landmarks.enumerated()), id: \.offset) { _, point in
                PointMark(x: .value("NM", point.distance), y: .value("ft", point.altitude))
                    .symbolSize(24)
                    .foregroundStyle(PanelTheme.checklistCyan)
                    .annotation(position: .top) {
                        Text(point.label ?? "")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
            }
            if let along, let altitude = model.liveFlight?.altitude {
                PointMark(x: .value("NM", along), y: .value("ft", altitude))
                    .symbol {
                        Image(systemName: "airplane")
                            .font(.system(size: large ? 18 : 14, weight: .bold))
                            .foregroundStyle(.yellow)
                    }
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...top)
        .chartPlotStyle { plot in plot.clipped() }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: large ? 8 : 5)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let miles = value.as(Double.self) { Text("\(Int(miles))").font(.system(size: 9)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let feet = value.as(Double.self) {
                        Text(feet >= 10_000 ? "FL\(Int(feet / 100))" : "\(Int(feet))").font(.system(size: 9))
                    }
                }
            }
        }
    }
}

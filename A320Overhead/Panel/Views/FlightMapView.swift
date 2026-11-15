import MapKit
import SwiftUI
import XPlaneKit

/// Moving map: the OFP route, the path flown, the aircraft, TOC/TOD and the airports of the
/// flight (origin, destination, alternates). Works without X-Plane too, as a route preview.
struct FlightMapView: View {
    /// Full screen adds a close button and a larger info strip.
    var fullScreen = false
    @Environment(PanelModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .automatic
    @State private var following = true
    @State private var distance: Double = 400_000
    @State private var satellite = false
    @State private var expanded = false
    /// The vertical display under the map, as on the A350.
    @State private var showsProfile = true

    private var route: [CLLocationCoordinate2D] {
        guard let ofp = model.ofp else { return [] }
        var points: [CLLocationCoordinate2D] = []
        if let lat = ofp.origin.latitude, let lon = ofp.origin.longitude { points.append(.init(latitude: lat, longitude: lon)) }
        points += ofp.fixes.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
        if let lat = ofp.destination.latitude, let lon = ofp.destination.longitude { points.append(.init(latitude: lat, longitude: lon)) }
        return points
    }

    private struct MapAirport: Identifiable {
        let airport: SimBriefOFP.Airport
        let role: String
        let icon: String
        let colour: Color
        var id: String { airport.icao + role }
    }

    private var airports: [MapAirport] {
        guard let ofp = model.ofp else { return [] }
        var list = [MapAirport(airport: ofp.origin, role: "Origen", icon: "airplane.departure", colour: PanelTheme.checklistCyan),
                    MapAirport(airport: ofp.destination, role: "Destino", icon: "airplane.arrival", colour: PanelTheme.checklistGreen)]
        if let alternate = ofp.alternate {
            list.append(MapAirport(airport: alternate, role: "Alterno", icon: "arrow.triangle.branch", colour: PanelTheme.checklistAmber))
        }
        list += (ofp.enrouteAlternates ?? []).map {
            MapAirport(airport: $0, role: "Alterno en ruta", icon: "cross.case", colour: .gray)
        }
        return list
    }

    /// TOC and TOD from the navlog ("ltlg" points).
    private var profilePoints: [SimBriefOFP.NavFix] {
        model.ofp?.fixes.filter { $0.type == "ltlg" && ["TOC", "TOD"].contains($0.ident) } ?? []
    }

    private var aircraft: CLLocationCoordinate2D? {
        model.liveFlight.map { .init(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                map
                infoStrip
            }
            .overlay(alignment: .bottomTrailing) { controls }
            if showsProfile {
                Divider().overlay(PanelTheme.checklistCyan.opacity(0.4))
                VerticalProfileView(large: fullScreen)
                    .frame(height: fullScreen ? 250 : 180)
            }
        }
        .onChange(of: model.liveFlight?.latitude) { _, _ in
            if following, let aircraft { position = .camera(MapCamera(centerCoordinate: aircraft, distance: distance)) }
        }
        .fullScreenCover(isPresented: $expanded) {
            FlightMapView(fullScreen: true)
        }
        .background(PanelTheme.checklistSurface)
    }

    private var map: some View {
        // No rotation: the aircraft symbol is drawn relative to north.
        Map(position: $position, interactionModes: [.pan, .zoom]) {
            if route.count > 1 {
                MapPolyline(coordinates: route)
                    .stroke(Color(red: 1.0, green: 0.4, blue: 1.0), lineWidth: 2.5)
            }
            if model.flownTrack.count > 1 {
                MapPolyline(coordinates: model.flownTrack.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                    .stroke(PanelTheme.checklistGreen, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            ForEach(airports) { item in
                if let lat = item.airport.latitude, let lon = item.airport.longitude {
                    Marker("\(item.airport.icao) · \(item.role)", systemImage: item.icon,
                           coordinate: .init(latitude: lat, longitude: lon))
                        .tint(item.colour)
                }
            }
            ForEach(Array(profilePoints.enumerated()), id: \.offset) { _, fix in
                Annotation(fix.ident, coordinate: .init(latitude: fix.latitude, longitude: fix.longitude)) {
                    Circle()
                        .fill(PanelTheme.checklistCyan)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                }
            }
            if let aircraft {
                Annotation("", coordinate: aircraft) {
                    Image(systemName: "airplane")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.yellow)
                        .shadow(color: .black, radius: 2)
                        // The symbol points east.
                        .rotationEffect(.degrees((model.liveFlight?.heading ?? 90) - 90))
                }
            }
        }
        .mapStyle(satellite ? .hybrid(elevation: .flat) : .standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            distance = context.camera.distance
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var infoStrip: some View {
        if let data = model.liveFlight {
            HStack(spacing: 14) {
                metric("ALT", "\(Int(data.altitude.rounded()))")
                metric("GS", "\(Int(data.groundspeed.rounded()))")
                if let togo = model.routeProgress?.distanceToGo {
                    metric("DIST", "\(Int(togo.rounded())) NM")
                }
                if let next = model.routeProgress.flatMap({ progress in model.ofp?.fixes.indices.contains(progress.next) == true ? model.ofp?.fixes[progress.next].ident : nil }) {
                    metric("SIG", next)
                }
                Spacer(minLength: 0)
                if fullScreen {
                    Button("Cerrar") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        } else {
            HStack {
                Label(model.ofp == nil ? "Carga un OFP de SimBrief para ver la ruta" : "Ruta del OFP · al conectar con X-Plane verás el avión",
                      systemImage: "map")
                    .font(.caption)
                Spacer(minLength: 0)
                if fullScreen {
                    Button("Cerrar") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            Text(value).font(.system(size: fullScreen ? 17 : 14, weight: .semibold).monospacedDigit())
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if aircraft != nil {
                Button {
                    following.toggle()
                    if following, let aircraft { position = .camera(MapCamera(centerCoordinate: aircraft, distance: distance)) }
                } label: {
                    Image(systemName: following ? "location.fill" : "location")
                }
                .accessibilityLabel(following ? "Dejar de seguir al avión" : "Seguir al avión")
            }
            Button {
                following = false
                position = .automatic
            } label: {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
            }
            .accessibilityLabel("Ver toda la ruta")
            Button {
                withAnimation { showsProfile.toggle() }
            } label: {
                Image(systemName: showsProfile ? "chart.xyaxis.line" : "rectangle.bottomhalf.inset.filled")
            }
            .accessibilityLabel(showsProfile ? "Ocultar el perfil vertical" : "Mostrar el perfil vertical")
            Button {
                satellite.toggle()
            } label: {
                Image(systemName: satellite ? "map" : "globe.europe.africa")
            }
            .accessibilityLabel(satellite ? "Mapa" : "Satélite")
            if !fullScreen {
                Button {
                    expanded = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .accessibilityLabel("Pantalla completa")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
    }
}

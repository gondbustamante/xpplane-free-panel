import SwiftUI
import XPlaneKit

/// Camera control: X-Plane views and quick looks, a hold-to-move pad, and the X-Camera views
/// found in the simulator. X-Camera registers one command per view with names that depend on
/// the user's setup, so they are listed from X-Plane rather than hard-coded.
struct CameraView: View {
    @Environment(PanelModel.self) private var model
    @State private var filter = ""

    private struct CameraPreset: Identifiable {
        let id: String
        let title: String
        let icon: String
    }

    private static let views: [CameraPreset] = [
        CameraPreset(id: "sim/view/3d_cockpit_cmnd_look", title: "Cabina 3D", icon: "person.fill"),
        CameraPreset(id: "sim/view/chase", title: "Persecución", icon: "airplane"),
        CameraPreset(id: "sim/view/circle", title: "Circular", icon: "arrow.triangle.2.circlepath"),
        CameraPreset(id: "sim/view/tower", title: "Torre", icon: "building.columns"),
        CameraPreset(id: "sim/view/runway", title: "Pista", icon: "road.lanes"),
        CameraPreset(id: "sim/view/free_camera", title: "Libre", icon: "video"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            HStack(alignment: .top, spacing: 22) {
                VStack(alignment: .leading, spacing: 22) {
                    card("Vistas de X-Plane") { viewButtons }
                    card("Vistas rápidas", footer: "Toca para ir. Mantén pulsado para guardar ahí la vista actual.") { quickLooks }
                }
                .frame(width: 360)
                card("Mover la cámara", footer: "Mantén pulsado: la cámara se mueve mientras tengas el dedo encima.") { movePad }
                    .frame(width: 300)
            }
            card("X-Camera") { xCamera }
                .frame(width: 682)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(PanelTheme.checklistSurface))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .disabled(model.status != .connected)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "video.fill")
                .font(.title2)
                .foregroundStyle(PanelTheme.checklistCyan)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cámaras")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text(model.status == .connected ? "Controla la vista de X-Plane y de X-Camera." : "Conecta con X-Plane para mover la cámara.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Sections

    private var viewButtons: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Self.views) { view in
                Button {
                    model.fireCamera(view.id)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: view.icon).font(.title3)
                        Text(view.title).font(.caption)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var quickLooks: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
            ForEach(0..<10, id: \.self) { index in
                Button {
                    model.fireCamera("sim/view/quick_look_\(index)")
                } label: {
                    Text("\(index + 1)")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
                .contextMenu {
                    Button("Guardar la vista actual en \(index + 1)", systemImage: "square.and.arrow.down") {
                        model.fireCamera("sim/view/quick_look_\(index)_mem")
                    }
                }
            }
        }
    }

    private var movePad: some View {
        VStack(spacing: 14) {
            Text("Desplazar").font(.caption).foregroundStyle(.secondary)
            pad(up: "sim/general/up", down: "sim/general/down", left: "sim/general/left", right: "sim/general/right")
            HStack(spacing: 8) {
                HoldButton(title: "Adelante", icon: "arrow.up.forward") { model.holdCamera("sim/general/forward", active: $0) }
                HoldButton(title: "Atrás", icon: "arrow.down.backward") { model.holdCamera("sim/general/backward", active: $0) }
            }
            Divider()
            Text("Girar").font(.caption).foregroundStyle(.secondary)
            pad(up: "sim/general/rot_up", down: "sim/general/rot_down", left: "sim/general/rot_left", right: "sim/general/rot_right")
            HStack(spacing: 8) {
                HoldButton(title: "Zoom +", icon: "plus.magnifyingglass") { model.holdCamera("sim/general/zoom_in", active: $0) }
                HoldButton(title: "Zoom −", icon: "minus.magnifyingglass") { model.holdCamera("sim/general/zoom_out", active: $0) }
            }
        }
    }

    private func pad(up: String, down: String, left: String, right: String) -> some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                HoldButton(icon: "chevron.up") { model.holdCamera(up, active: $0) }
                Color.clear.frame(width: 1, height: 1)
            }
            GridRow {
                HoldButton(icon: "chevron.left") { model.holdCamera(left, active: $0) }
                Image(systemName: "circle.dotted").foregroundStyle(.tertiary)
                HoldButton(icon: "chevron.right") { model.holdCamera(right, active: $0) }
            }
            GridRow {
                Color.clear.frame(width: 1, height: 1)
                HoldButton(icon: "chevron.down") { model.holdCamera(down, active: $0) }
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }

    @ViewBuilder
    private var xCamera: some View {
        let commands = model.xCameraCommands.filter {
            filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) || $0.name.localizedCaseInsensitiveContains(filter)
        }
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    model.searchXCameraCommands()
                } label: {
                    Label(model.xCameraCommands.isEmpty ? "Buscar vistas de X-Camera" : "Actualizar", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                if model.xCameraCommands.count > 9 {
                    TextField("Filtrar", text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                }
                Spacer(minLength: 0)
                searchState
            }
            if model.xCameraCommands.isEmpty {
                Text("X-Camera crea un comando por cada vista que guardas. Pulsa «Buscar» con X-Plane y X-Camera en marcha y aparecerán aquí.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(commands) { command in
                        Button {
                            model.fireCamera(command.name)
                        } label: {
                            Text(command.title)
                                .font(.callout)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .help(command.name)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var searchState: some View {
        switch model.cameraSearchState {
        case .idle:
            EmptyView()
        case .searching:
            ProgressView()
        case .found(let count):
            Text(count == 0 ? "X-Camera no está instalado o no expone comandos." : "\(count) comandos")
                .font(.caption)
                .foregroundStyle(count == 0 ? PanelTheme.checklistAmber : .secondary)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(PanelTheme.checklistAmber)
                .lineLimit(2)
        }
    }

    private func card<Content: View>(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
            content()
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

/// Button that keeps a command active while it is held, and releases it on lift or cancel.
private struct HoldButton: View {
    var title: String? = nil
    let icon: String
    let onHold: (Bool) -> Void
    @State private var pressed = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            if let title { Text(title).font(.caption) }
        }
        .frame(minWidth: 52, maxWidth: title == nil ? 52 : .infinity, minHeight: 44)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(pressed ? PanelTheme.checklistCyan.opacity(0.35) : Color.white.opacity(0.10)))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressed else { return }
                    pressed = true
                    onHold(true)
                }
                .onEnded { _ in
                    pressed = false
                    onHold(false)
                }
        )
        .onDisappear {
            if pressed { onHold(false) }
        }
        .accessibilityElement()
        .accessibilityLabel(title ?? icon)
        .accessibilityAction {
            onHold(true)
            onHold(false)
        }
    }
}

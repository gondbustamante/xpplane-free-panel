import SwiftUI

struct ConnectionBar: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var showSettings: Bool
    @Binding var showDiagnostics: Bool

    private var statusColor: Color {
        switch model.status {
        case .connected: return model.demoMode ? .cyan : .green
        case .connecting, .reconnecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    /// Narrow window (portrait on smaller iPads, Split View): drop the secondary items.
    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(model.statusLabel)
                .font(.footnote)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if !model.unresolved.isEmpty && !compact {
                Text("· \(model.unresolved.count) dataref(s) no disponibles")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Spacer(minLength: 8)
            if !compact {
                Text(model.demoMode ? "Simulación local" : "\(model.host):\(String(model.port))")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            HStack(spacing: 2) {
                if !compact {
                    Button { model.zoom(by: 1 / 1.15) } label: { Image(systemName: "minus.magnifyingglass") }
                    Text("\(Int((model.canvasScale * 100).rounded()))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 38)
                    Button { model.zoom(by: 1.15) } label: { Image(systemName: "plus.magnifyingglass") }
                }
                Button { model.requestFit() } label: { Image(systemName: "arrow.down.left.and.arrow.up.right.rectangle") }
                    .help("Ajustar al ancho")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if !model.status.isActive && !model.demoMode {
                Button("Demo") { model.startDemo() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Probar el panel sin X-Plane")
            }
            Button(model.status.isActive ? "Desconectar" : "Conectar") {
                model.toggleConnection()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button {
                showDiagnostics = true
            } label: {
                Image(systemName: "stethoscope")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

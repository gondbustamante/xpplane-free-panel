import SwiftUI

struct ConnectionBar: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var showSettings: Bool
    @Binding var showDiagnostics: Bool

    /// Narrow window (portrait on smaller iPads, Split View): drop the secondary items.
    private var compact: Bool { sizeClass == .compact }

    var body: some View {
        HStack(spacing: compact ? 8 : 12) {
            ConnectionStatusMenu(showSettings: $showSettings, showDiagnostics: $showDiagnostics)
                .layoutPriority(1)
            // Only the action you need right now: connecting. Disconnecting lives in the menu.
            if !model.status.isActive {
                Button("Conectar") { model.connect() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                if !model.demoMode && !compact {
                    Button("Probar demo") { model.startDemo() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Probar el panel sin X-Plane")
                }
            }
            Spacer(minLength: 8)
            ZoomControls(compact: compact)
        }
    }
}

/// Status chip: dot, state and destination. Tapping it opens every connection action plus the
/// way into settings and diagnostics, so the bar keeps a single button at most.
private struct ConnectionStatusMenu: View {
    @Environment(PanelModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var showSettings: Bool
    @Binding var showDiagnostics: Bool

    private var destination: String {
        model.demoMode ? "Simulación local" : "\(model.host):\(String(model.port))"
    }

    var body: some View {
        Menu {
            Section(destination) {
                if model.status.isActive {
                    Button("Desconectar", systemImage: "bolt.slash", role: .destructive) { model.disconnect() }
                    if !model.demoMode {
                        Button("Reconectar", systemImage: "arrow.clockwise") { model.connect() }
                    }
                } else {
                    Button("Conectar", systemImage: "bolt") { model.connect() }
                }
                if model.demoMode {
                    Button("Usar X-Plane", systemImage: "desktopcomputer") { model.demoMode = false }
                } else {
                    Button("Probar modo demo", systemImage: "play.circle") { model.startDemo() }
                }
            }
            Section {
                Button("Ajustes…", systemImage: "gearshape") { showSettings = true }
                Button("Diagnóstico de datarefs…", systemImage: "stethoscope") { showDiagnostics = true }
            }
        } label: {
            HStack(spacing: 8) {
                Circle().fill(model.statusColor).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.statusLabel)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white)
                    if sizeClass != .compact {
                        Text(destination)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .lineLimit(1)
                .truncationMode(.tail)
                if !model.unresolved.isEmpty {
                    Label("\(model.unresolved.count)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .help("\(model.unresolved.count) dataref(s) no disponibles")
                }
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.white.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("Conexión: \(model.statusLabel)")
        .accessibilityHint("Abre las opciones de conexión y los ajustes")
    }
}

private struct ZoomControls: View {
    @Environment(PanelModel.self) private var model
    let compact: Bool

    var body: some View {
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
    }
}

extension PanelModel {
    /// Status dot: green connected, cyan in demo mode, yellow connecting, red on error.
    var statusColor: Color {
        switch status {
        case .connected: return demoMode ? .cyan : .green
        case .connecting, .reconnecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }
}

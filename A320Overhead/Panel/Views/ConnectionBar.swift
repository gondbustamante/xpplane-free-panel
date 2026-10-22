import SwiftUI

struct ConnectionBar: View {
    @Environment(PanelModel.self) private var model
    @Binding var showSettings: Bool
    @Binding var showDiagnostics: Bool

    private var statusColor: Color {
        switch model.status {
        case .connected: return .green
        case .connecting, .reconnecting: return .yellow
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(statusColor).frame(width: 10, height: 10)
            Text(model.status.label)
                .font(.footnote)
                .foregroundStyle(.white)
                .lineLimit(1)
            if !model.unresolved.isEmpty {
                Text("· \(model.unresolved.count) dataref(s) no disponibles")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text("\(model.host):\(String(model.port))")
                .font(.footnote.monospaced())
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 2) {
                Button { model.zoom(by: 1 / 1.15) } label: { Image(systemName: "minus.magnifyingglass") }
                Text("\(Int((model.canvasScale * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 38)
                Button { model.zoom(by: 1.15) } label: { Image(systemName: "plus.magnifyingglass") }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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

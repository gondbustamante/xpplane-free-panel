import SwiftUI

struct ConnectionBar: View {
    @Environment(PanelModel.self) private var model
    @Binding var showSettings: Bool

    private var statusColor: Color {
        switch model.status {
        case .connected: return .green
        case .connecting: return .yellow
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
            Button(model.status == .connected || model.status == .connecting ? "Desconectar" : "Conectar") {
                model.toggleConnection()
            }
            .buttonStyle(.borderedProminent)
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

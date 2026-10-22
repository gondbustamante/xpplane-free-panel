import SwiftUI
import XPlaneKit

struct RootView: View {
    @Environment(PanelModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            ConnectionBar(showSettings: $showSettings)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                OverheadView()
                    .padding(24)
            }
        }
        .background(PanelTheme.cockpitBackground.ignoresSafeArea())
        .sheet(isPresented: $showSettings) {
            ConnectionSettingsView()
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
    }
}

/// The overhead face: subpanels laid out left to right. Grows as more mapping files are added.
struct OverheadView: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            if model.subpanels.isEmpty {
                Text("No hay subpaneles cargados. Revisa la carpeta mapping/.")
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(40)
            }
            ForEach(model.subpanels) { panel in
                SubpanelView(panel: panel)
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(colors: [PanelTheme.panelFaceHighlight, PanelTheme.panelFace],
                                     startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 12, y: 6)
        )
    }
}

struct SubpanelView: View {
    let panel: SubpanelDefinition
    @Environment(PanelModel.self) private var model

    private var rows: [Int] {
        Array(Set(panel.controls.map(\.row))).sorted()
    }

    private func controls(in row: Int) -> [ControlDefinition] {
        panel.controls.filter { $0.row == row }.sorted { $0.col < $1.col }
    }

    var body: some View {
        Grid(alignment: .top, horizontalSpacing: 20, verticalSpacing: 18) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(controls(in: row)) { control in
                        ControlView(control: control)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 18)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.9), lineWidth: 1.5)
        )
        .overlay(alignment: .topLeading) {
            Text(panel.title.uppercased())
                .font(.system(size: 12.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .background(PanelTheme.panelFace)
                .offset(x: 12, y: -9)
        }
    }
}

/// Picks the right widget for a control definition and wires it to the model.
struct ControlView: View {
    let control: ControlDefinition
    @Environment(PanelModel.self) private var model

    var body: some View {
        ZStack(alignment: .topTrailing) {
            widget
            if model.showVerificationBadges && !control.isVerified {
                Circle()
                    .fill(PanelTheme.verificationBadge)
                    .frame(width: 7, height: 7)
                    .offset(x: 6, y: -2)
                    .help(control.notes ?? "Mapeo pendiente de verificar")
            }
        }
    }

    @ViewBuilder
    private var widget: some View {
        switch control.kind {
        case .toggle2, .toggle3:
            ToggleSwitchView(label: control.label,
                             positions: control.positions,
                             position: model.position(of: control),
                             enabled: model.isAvailable(control)) { delta in
                model.move(control, by: delta)
            }
        case .korry:
            KorryButtonView(label: control.label,
                            top: lamp(control.lamps?.top),
                            bottom: lamp(control.lamps?.bottom),
                            enabled: model.isAvailable(control) || control.state == nil && model.status == .connected) {
                model.press(control)
            }
        }
    }

    private func lamp(_ definition: Lamp?) -> KorryLamp? {
        guard let definition else { return nil }
        return KorryLamp(text: definition.text,
                         color: PanelTheme.lamp(definition.color),
                         lit: model.isLit(definition))
    }
}

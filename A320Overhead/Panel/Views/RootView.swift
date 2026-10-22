import SwiftUI
import XPlaneKit

struct RootView: View {
    @Environment(PanelModel.self) private var model
    @State private var showSettings = false
    @State private var showDiagnostics = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
        } detail: {
            VStack(spacing: 0) {
                ConnectionBar(showSettings: $showSettings, showDiagnostics: $showDiagnostics)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                PanelCanvas()
            }
            .background(PanelTheme.cockpitBackground.ignoresSafeArea())
            .navigationTitle(model.selectionTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(PanelTheme.cockpitBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showSettings) {
            ConnectionSettingsView()
        }
        .sheet(isPresented: $showDiagnostics) {
            DiagnosticsView()
        }
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
    }
}

struct SubpanelView: View {
    let panel: SubpanelDefinition
    @Environment(PanelModel.self) private var model

    private var rows: [Int] {
        Array(Set(panel.controls.map(\.gridRow))).sorted()
    }

    private func controls(in row: Int) -> [ControlDefinition] {
        panel.controls.filter { $0.gridRow == row }.sorted { $0.gridColumn < $1.gridColumn }
    }

    var body: some View {
        Grid(alignment: .top, horizontalSpacing: 12, verticalSpacing: 12) {
            ForEach(rows, id: \.self) { row in
                GridRow {
                    ForEach(controls(in: row)) { control in
                        ControlView(control: control)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(Color.white.opacity(0.92), lineWidth: 1.4)
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
        .overlay(alignment: .topTrailing) { ScrewView().offset(x: -5, y: -4) }
        .overlay(alignment: .bottomLeading) { ScrewView().offset(x: 5, y: 4) }
        .overlay(alignment: .bottomTrailing) { ScrewView().offset(x: -5, y: 4) }
        .padding(4)
    }
}

/// Picks the right widget for a control definition and wires it to the model.
struct ControlView: View {
    let control: ControlDefinition
    @Environment(PanelModel.self) private var model

    var body: some View {
        ZStack(alignment: .topTrailing) {
            widget
            if model.showVerificationBadges && (!control.isVerified || control.isReadOnly) {
                Image(systemName: control.isReadOnly ? "lock.fill" : "circle.fill")
                    .font(.system(size: control.isReadOnly ? 9 : 7))
                    .foregroundStyle(PanelTheme.verificationBadge)
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
                             enabled: model.isAvailable(control),
                             dimmed: model.isDimmed(control)) { delta in
                model.move(control, by: delta)
            }
        case .rotary:
            RotarySelectorView(label: control.label,
                               positions: control.positions,
                               position: model.position(of: control),
                               enabled: model.isAvailable(control),
                               dimmed: model.isDimmed(control)) { delta in
                model.move(control, by: delta)
            }
        case .knob, .display:
            AbsoluteControlView(control: control)
                .frame(width: 80, height: 60)
        case .korry:
            KorryButtonView(label: control.label,
                            top: lamp(control.lamps?.top),
                            bottom: lamp(control.lamps?.bottom),
                            guarded: control.guarded ?? false,
                            enabled: model.isAvailable(control),
                            dimmed: model.isDimmed(control)) {
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

import SwiftUI
import XPlaneKit

/// The panel face for the current selection. Groups with an arrangement in `layout.json` are
/// drawn in their physical columns and rows (only the visible subpanels, so a flight phase keeps
/// the overhead's geography); groups without one flow left to right. Panels with their own view
/// (the FCU) come first, as the glareshield sits in front of the overhead.
struct PanelCanvas: View {
    @Environment(PanelModel.self) private var model

    var body: some View {
        let items = model.visibleItems
        ZoomableCanvas {
            if model.selection.isCustom {
                CustomPanelCanvas(panel: model.selectedCustomPanel, items: items)
            } else {
                StandardCanvas(items: items)
            }
        }
    }
}

/// Phases, groups and sections: FCU and MCDU first, then each group in its real geography.
private struct StandardCanvas: View {
    let items: [PanelItem]
    @Environment(PanelModel.self) private var model

    var body: some View {
            VStack(alignment: .leading, spacing: 30) {
                if items.isEmpty {
                    Text("No hay paneles para esta selección. Revisa mapping/layout.json.")
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(40)
                }
                if items.contains(where: { if case .fcu = $0 { return true } else { return false } }) {
                    FCUView()
                }
                if items.contains(where: { if case .mcdu = $0 { return true } else { return false } }) {
                    MCDUView()
                }
                ForEach(model.layout.groups) { group in
                    let visible = model.visibleSubpanels(in: group.id)
                    if !visible.isEmpty {
                        let absolute = visible.values.filter(\.isAbsolute)
                        if let canvas = model.layout.canvas(for: group.id), !absolute.isEmpty {
                            AbsoluteGroupView(canvas: canvas, panels: absolute.sorted { $0.id < $1.id })
                        } else {
                            PanelFace {
                                if let arrangement = model.layout.arrangement(for: group.id) {
                                    ArrangedGroupView(arrangement: arrangement, panels: visible)
                                } else {
                                    FlowLayout(spacing: 26) {
                                        ForEach(visible.values.sorted { ($0.order ?? .max, $0.title) < ($1.order ?? .max, $1.title) }) { panel in
                                            SubpanelView(panel: panel)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
    }
}

/// A user-built panel: its items in the chosen order, `columns` per row. Overhead sections keep
/// their real artwork and proportions; each one is cropped to itself.
private struct CustomPanelCanvas: View {
    let panel: CustomPanel?
    let items: [PanelItem]
    @Environment(PanelModel.self) private var model

    private var rows: [[PanelItem]] {
        let columns = max(panel?.columns ?? 2, 1)
        return stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "square.grid.2x2").font(.system(size: 40))
                    Text("Este panel está vacío.")
                    Text("Edítalo desde la barra lateral para añadir secciones, el FCU o el MCDU.")
                        .font(.footnote)
                }
                .foregroundStyle(.white.opacity(0.7))
                .padding(60)
            }
            ForEach(rows.indices, id: \.self) { row in
                HStack(alignment: .top, spacing: 24) {
                    ForEach(rows[row]) { item in
                        itemView(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func itemView(_ item: PanelItem) -> some View {
        switch item {
        case .fcu:
            FCUView()
        case .mcdu:
            MCDUView()
        case .subpanel(let subpanel):
            if subpanel.isAbsolute, let canvas = model.layout.canvas(for: subpanel.groupID) {
                AbsoluteGroupView(canvas: canvas, panels: [subpanel])
            } else {
                PanelFace { SubpanelView(panel: subpanel) }
            }
        }
    }
}

/// Grey Airbus panel face behind a group of subpanels.
struct PanelFace<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(26)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [PanelTheme.panelFaceHighlight, PanelTheme.panelFace],
                                             startPoint: .top, endPoint: .bottom))
                    RoundedRectangle(cornerRadius: 8)
                        .fill(RadialGradient(colors: [Color.clear, Color.black.opacity(0.10)],
                                             center: .center, startRadius: 500, endRadius: 1400))
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PanelTheme.panelEdge, lineWidth: 3)
                }
                .shadow(color: .black.opacity(0.65), radius: 14, y: 8)
            )
    }
}

/// Columns of rows of subpanels, as declared in the group's arrangement. Ids that are not
/// visible are skipped; empty rows and columns collapse. Subpanels of the group that the
/// arrangement does not mention are appended underneath.
struct ArrangedGroupView: View {
    let arrangement: PanelArrangement
    let panels: [String: SubpanelDefinition]

    private var columns: [[[SubpanelDefinition]]] {
        arrangement.columns.map { column in
            column.map { row in row.compactMap { panels[$0] } }.filter { !$0.isEmpty }
        }
    }

    private var unplaced: [SubpanelDefinition] {
        let placed = arrangement.placedIDs
        return panels.values.filter { !placed.contains($0.id) }.sorted { $0.title < $1.title }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top, spacing: 18) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, rows in
                    if !rows.isEmpty {
                        VStack(alignment: .center, spacing: 14) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                HStack(alignment: .top, spacing: 14) {
                                    ForEach(row) { panel in
                                        SubpanelView(panel: panel)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            if !unplaced.isEmpty {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(unplaced) { panel in
                        SubpanelView(panel: panel)
                    }
                }
            }
        }
    }
}

/// Lays out its single child at its ideal size and claims that size multiplied by `scale`.
/// Pair it with `.scaleEffect(scale, anchor: .topLeading)` on the child.
struct ScaledLayout: Layout {
    var scale: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(.unspecified)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        child.place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
    }
}

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
            VStack(alignment: .leading, spacing: 30) {
                if items.isEmpty {
                    Text("No hay paneles para esta selección. Revisa mapping/layout.json.")
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(40)
                }
                if items.contains(where: { if case .fcu = $0 { return true } else { return false } }) {
                    FCUView()
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

/// Scrolls in both directions and scales its content with a pinch or the model's zoom.
/// `ScaledLayout` reports the scaled size to the scroll view while the content is laid out at its
/// natural size, so there is no measuring round-trip and the scroll area always matches.
struct ZoomableCanvas<Content: View>: View {
    @Environment(PanelModel.self) private var model
    @ViewBuilder let content: () -> Content

    @State private var pinchBase: Double?
    @State private var naturalSize: CGSize = .zero
    @State private var containerSize: CGSize = .zero
    @State private var pendingFit = true

    private let margin: CGFloat = 20

    /// True when the scaled content fits the container: then the scroll view is disabled so a
    /// finger on a switch never drags the panel around.
    private var fits: Bool {
        guard naturalSize.width > 0, containerSize.width > 0 else { return true }
        let scale = model.canvasScale
        return naturalSize.width * scale + margin * 2 <= containerSize.width + 1
            && naturalSize.height * scale + margin * 2 <= containerSize.height + 1
    }

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            ScaledLayout(scale: model.canvasScale) {
                content()
                    // Read-only measurement of the natural size, used for "fit to width".
                    // It feeds nothing back into layout, so there is no oscillation.
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: NaturalSizeKey.self, value: proxy.size)
                    })
                    .scaleEffect(model.canvasScale, anchor: .topLeading)
            }
            .padding(margin)
            .frame(minWidth: containerSize.width, minHeight: containerSize.height, alignment: .center)
        }
        .scrollDisabled(fits)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: ContainerSizeKey.self, value: proxy.size)
        })
        .onPreferenceChange(NaturalSizeKey.self) { size in
            naturalSize = size
            applyFitIfPending()
        }
        .onPreferenceChange(ContainerSizeKey.self) { size in
            containerSize = size
            applyFitIfPending()
        }
        .onChange(of: model.fitRequestID, initial: true) { _, id in
            guard id > 0 else { return }
            pendingFit = true
            applyFitIfPending()
        }
        .onChange(of: model.selection) { _, _ in
            pendingFit = true   // new selection: refit once its size is known
            DispatchQueue.main.async { applyFitIfPending() }
        }
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    if pinchBase == nil { pinchBase = model.canvasScale }
                    model.pinch(to: (pinchBase ?? 1) * value)
                }
                .onEnded { _ in pinchBase = nil }
        )
    }
}

private extension ZoomableCanvas {
    /// Fits both axes so the selection is visible whole and the canvas stays still.
    func applyFitIfPending() {
        guard pendingFit || model.autoFit, naturalSize.width > 0, naturalSize.height > 0, containerSize.width > 0 else { return }
        let availableWidth = containerSize.width - margin * 2 - 4
        let availableHeight = containerSize.height - margin * 2 - 4
        let target = min(availableWidth / naturalSize.width, availableHeight / naturalSize.height)
        // Ignore sub-pixel differences so a refit never nudges the panel under a finger.
        if abs(target - model.canvasScale) > 0.002 { model.setScale(target) }
        pendingFit = false
    }
}

private struct NaturalSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

private struct ContainerSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
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

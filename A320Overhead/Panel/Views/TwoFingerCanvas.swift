import SwiftUI
import UIKit

/// The panel canvas. One finger always operates controls; two fingers pan and pinch.
///
/// SwiftUI's `ScrollView` cannot require two fingers to scroll, so the canvas is a `UIScrollView`
/// whose pan gesture needs two touches, with the SwiftUI panel hosted inside it. Zoom stays in
/// SwiftUI (`canvasScale` + `ScaledLayout`), which keeps text and lines crisp at any scale;
/// the scroll view only pans, and a two-finger pinch drives `canvasScale`.
///
/// While `model.autoFit` is on, the selection is kept fitted to the screen and centred, so there
/// is nothing to pan and the panel never moves under a finger.
struct ZoomableCanvas<Content: View>: View {
    @Environment(PanelModel.self) private var model
    @ViewBuilder let content: () -> Content

    var body: some View {
        TwoFingerCanvas(model: model,
                        autoFit: model.autoFit,
                        fitRequestID: model.fitRequestID,
                        selection: model.selection,
                        content: AnyView(content()))
    }
}

/// Sizes reported by the hosted panel: natural (unscaled) and as laid out at the current scale.
struct CanvasSizes: Equatable {
    var natural: CGSize
    var scaled: CGSize
}

/// Hosted inside the scroll view: lays the panel out at the model's scale and reports its sizes.
private struct ScaledCanvasContent: View {
    @Environment(PanelModel.self) private var model
    let content: AnyView
    let onSizes: (CanvasSizes) -> Void

    @State private var natural: CGSize = .zero

    var body: some View {
        let scale = model.canvasScale
        ScaledLayout(scale: scale) {
            content
                .fixedSize()
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: CanvasNaturalSizeKey.self, value: proxy.size)
                })
                .scaleEffect(scale, anchor: .topLeading)
        }
        .onPreferenceChange(CanvasNaturalSizeKey.self) { size in
            natural = size
            report(natural: size, scale: scale)
        }
        .onChange(of: model.canvasScale) { _, newScale in
            report(natural: natural, scale: newScale)
        }
    }

    private func report(natural: CGSize, scale: Double) {
        guard natural.width > 0, natural.height > 0 else { return }
        onSizes(CanvasSizes(natural: natural,
                            scaled: CGSize(width: natural.width * scale, height: natural.height * scale)))
    }
}

private struct CanvasNaturalSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}

/// Scroll view that tells its coordinator when its bounds change (rotation, sidebar toggle).
final class CanvasScrollView: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}

struct TwoFingerCanvas: UIViewRepresentable {
    let model: PanelModel
    let autoFit: Bool
    let fitRequestID: Int
    let selection: PanelSelection
    let content: AnyView

    func makeCoordinator() -> CanvasCoordinator {
        CanvasCoordinator(model: model)
    }

    func makeUIView(context: Context) -> CanvasScrollView {
        let scrollView = CanvasScrollView()
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        // The whole point: one finger belongs to the controls, two fingers move the panel.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        scrollView.panGestureRecognizer.maximumNumberOfTouches = 2
        // Deliver touches to switches immediately; a second finger landing cancels the press.
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        // Zoom is handled in SwiftUI, not by the scroll view's own zooming.
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 1

        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        scrollView.addSubview(host.view)

        context.coordinator.attach(scrollView: scrollView, host: host)
        return scrollView
    }

    func updateUIView(_ scrollView: CanvasScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.model = model
        coordinator.host?.rootView = AnyView(
            ScaledCanvasContent(content: content) { [weak coordinator] sizes in
                coordinator?.sizesChanged(sizes)
            }
            .environment(model)
        )
        coordinator.modelChanged(autoFit: autoFit, fitRequestID: fitRequestID, selection: selection)
    }
}

final class CanvasCoordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    var model: PanelModel
    weak var scrollView: CanvasScrollView?
    var host: UIHostingController<AnyView>?

    private var sizes = CanvasSizes(natural: .zero, scaled: .zero)
    private var lastBounds: CGSize = .zero
    private var lastFitRequestID = -1
    private var lastSelection: PanelSelection?
    private var pinchBase: Double = 1
    private let margin: CGFloat = 20

    init(model: PanelModel) {
        self.model = model
    }

    func attach(scrollView: CanvasScrollView, host: UIHostingController<AnyView>) {
        self.scrollView = scrollView
        self.host = host
        scrollView.delegate = self
        scrollView.onLayout = { [weak self] in self?.boundsMaybeChanged() }

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        scrollView.addGestureRecognizer(pinch)
    }

    // MARK: Updates

    func sizesChanged(_ newSizes: CanvasSizes) {
        guard let scrollView, let host, newSizes != sizes else { return }
        sizes = newSizes
        host.view.frame = CGRect(origin: .zero, size: newSizes.scaled)
        scrollView.contentSize = newSizes.scaled
        if model.autoFit { fit() } else { center(resetOffset: false) }
    }

    func modelChanged(autoFit: Bool, fitRequestID: Int, selection: PanelSelection) {
        let selectionChanged = selection != lastSelection
        let fitRequested = fitRequestID != lastFitRequestID
        lastSelection = selection
        lastFitRequestID = fitRequestID
        // A new selection is measured on the next pass and refitted in sizesChanged.
        if autoFit && (fitRequested || !selectionChanged) { fit() }
    }

    private func boundsMaybeChanged() {
        guard let scrollView, scrollView.bounds.size != lastBounds else { return }
        lastBounds = scrollView.bounds.size
        if model.autoFit { fit() } else { center(resetOffset: false) }
    }

    // MARK: Fit and centre

    /// Scale at which the natural content fits the visible area with a margin.
    private func fitScale() -> Double? {
        guard let scrollView, sizes.natural.width > 0, sizes.natural.height > 0,
              scrollView.bounds.width > 0, scrollView.bounds.height > 0 else { return nil }
        let width = (scrollView.bounds.width - margin * 2) / sizes.natural.width
        let height = (scrollView.bounds.height - margin * 2) / sizes.natural.height
        let target = Double(min(width, height))
        return min(max(target, PanelModel.scaleRange.lowerBound), PanelModel.scaleRange.upperBound)
    }

    private func fit() {
        guard let target = fitScale() else { return }
        center(resetOffset: true)
        // Ignore sub-pixel differences so a refit never nudges the panel under a finger.
        if abs(model.canvasScale - target) > 0.002 {
            let model = self.model
            Task { @MainActor in model.setScale(target) }
        }
    }

    /// Centres content smaller than the screen; keeps a margin around content larger than it.
    private func center(resetOffset: Bool) {
        guard let scrollView else { return }
        let content = scrollView.contentSize
        let bounds = scrollView.bounds.size
        let horizontal = max((bounds.width - content.width) / 2, margin)
        let vertical = max((bounds.height - content.height) / 2, margin)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if scrollView.contentInset != inset {
            scrollView.contentInset = inset
        }
        let fitsWidth = content.width + inset.left + inset.right <= bounds.width + 1
        let fitsHeight = content.height + inset.top + inset.bottom <= bounds.height + 1
        if resetOffset || (fitsWidth && fitsHeight) {
            let target = CGPoint(x: fitsWidth ? -inset.left : scrollView.contentOffset.x,
                                 y: fitsHeight ? -inset.top : scrollView.contentOffset.y)
            if scrollView.contentOffset != target {
                scrollView.contentOffset = target
            }
        }
    }

    // MARK: Pinch

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let scrollView else { return }
        switch gesture.state {
        case .began:
            pinchBase = model.canvasScale
        case .changed:
            let old = model.canvasScale
            let new = min(max(pinchBase * Double(gesture.scale), PanelModel.scaleRange.lowerBound),
                          PanelModel.scaleRange.upperBound)
            guard abs(new - old) > 0.001 else { return }
            // Keep the point under the fingers where it is.
            let location = gesture.location(in: scrollView)          // content coordinates
            let onScreen = CGPoint(x: location.x - scrollView.contentOffset.x,
                                   y: location.y - scrollView.contentOffset.y)
            let ratio = CGFloat(new / old)
            model.pinch(to: new)
            scrollView.contentOffset = CGPoint(x: location.x * ratio - onScreen.x,
                                               y: location.y * ratio - onScreen.y)
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // Pinch and two-finger pan together, like Maps.
        gestureRecognizer is UIPinchGestureRecognizer && other === scrollView?.panGestureRecognizer
    }
}

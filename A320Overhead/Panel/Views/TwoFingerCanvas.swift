import SwiftUI
import UIKit

// Panel canvas: one finger operates controls; two fingers pan and pinch.
//
// How it works (the pattern used by PDF, map and chart viewers):
// - A `UIScrollView` owns navigation. Its pan gesture requires two touches, so a single finger
//   always reaches the switch under it. Pinch is the scroll view's native zoom.
// - The SwiftUI panel lives in a child `UIHostingController`, properly contained in a view
//   controller so it inherits dark mode, keyboard focus and size changes.
// - During a pinch iOS scales the hosted view with a transform (smooth). When the fingers lift,
//   the panel is re-laid out by SwiftUI at the new scale and the transform is reset, so text and
//   lines are sharp at every zoom level.
// - Sizes are measured synchronously with `sizeThatFits` (natural size × scale): no preference
//   round-trips, so the scrollable area always matches what is drawn.
// - "Fit" fills the width when that needs little vertical travel (the overhead), otherwise it
//   shows the whole page (a single section, the MCDU). It is re-applied on rotation, split view
//   and sidebar changes until the user zooms by hand. A two-finger tap toggles between fit and
//   touch size around the tapped point.

struct ZoomableCanvas<Content: View>: View {
    @Environment(PanelModel.self) private var model
    @ViewBuilder let content: () -> Content

    var body: some View {
        PanelCanvasRepresentable(model: model,
                                 scale: model.canvasScale,
                                 autoFit: model.autoFit,
                                 fitRequestID: model.fitRequestID,
                                 selection: model.selection,
                                 revision: model.layoutRevision,
                                 content: AnyView(content()))
    }
}

/// The panel laid out at `scale`. `ScaledLayout` claims natural size × scale, so the hosting
/// view's frame and the scroll view's content size match exactly what is drawn.
private struct ScaledCanvas: View {
    let scale: Double
    let content: AnyView

    var body: some View {
        ScaledLayout(scale: scale) {
            content
                .fixedSize()
                .scaleEffect(scale, anchor: .topLeading)
        }
    }
}

struct PanelCanvasRepresentable: UIViewControllerRepresentable {
    let model: PanelModel
    let scale: Double
    let autoFit: Bool
    let fitRequestID: Int
    let selection: PanelSelection
    let revision: Int
    let content: AnyView

    func makeUIViewController(context: Context) -> PanelCanvasController {
        PanelCanvasController(model: model)
    }

    func updateUIViewController(_ controller: PanelCanvasController, context: Context) {
        controller.update(model: model, content: content, scale: scale, autoFit: autoFit,
                          fitRequestID: fitRequestID, selection: selection, revision: revision)
    }
}

final class PanelCanvasController: UIViewController, UIScrollViewDelegate {
    private var model: PanelModel
    private let scrollView = UIScrollView()
    private let host = UIHostingController(rootView: AnyView(EmptyView()))
    /// Off-screen controller used only to measure the panel's natural size.
    private let measurer = UIHostingController(rootView: AnyView(EmptyView()))

    private var content = AnyView(EmptyView())
    private var naturalSize: CGSize = .zero
    private var renderedScale: Double = 0
    private var lastSelection: PanelSelection?
    private var lastFitRequestID = -1
    private var lastRevision = -1
    private var lastBounds: CGSize = .zero
    /// Natural-coordinate point to bring to the centre after the next render (two-finger tap).
    private var pendingFocus: CGPoint?
    private let margin: CGFloat = 20
    /// Scale at which Korry buttons are about 42 pt: the "touch size" of the two-finger tap.
    private let touchScale: Double = 1.0

    init(model: PanelModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        overrideUserInterfaceStyle = .dark

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.backgroundColor = .clear
        scrollView.delegate = self
        scrollView.contentInsetAdjustmentBehavior = .never
        // One finger belongs to the controls; two fingers move the panel.
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        scrollView.panGestureRecognizer.maximumNumberOfTouches = 2
        // Touches reach switches immediately; a second finger landing cancels the press.
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.bouncesZoom = true
        scrollView.alwaysBounceVertical = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.showsVerticalScrollIndicator = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.indicatorStyle = .white
        view.addSubview(scrollView)

        addChild(host)
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        scrollView.addSubview(host.view)
        host.didMove(toParent: self)

        measurer.safeAreaRegions = []

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.numberOfTapsRequired = 1
        scrollView.addGestureRecognizer(twoFingerTap)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let size = scrollView.bounds.size
        guard size.width > 0, size.height > 0, size != lastBounds else { return }
        lastBounds = size
        if naturalSize == .zero { measure() }
        if model.autoFit {
            applyFit()
        } else if renderedScale == 0 {
            render(at: model.canvasScale)          // first layout after a manual zoom
            centerContent(resetOffset: true)
        } else {
            updateZoomLimits()
            centerContent(resetOffset: false)
        }
    }

    // MARK: SwiftUI → UIKit

    func update(model: PanelModel, content: AnyView, scale: Double, autoFit: Bool,
                fitRequestID: Int, selection: PanelSelection, revision: Int) {
        self.model = model
        self.content = content
        // A different selection, or the same one with new content (custom panel edited,
        // orientation, MCDU layout), is treated as new content: measure and place it again.
        let selectionChanged = selection != lastSelection || revision != lastRevision
        let fitRequested = fitRequestID != lastFitRequestID
        lastSelection = selection
        lastFitRequestID = fitRequestID
        lastRevision = revision
        guard isViewLoaded else { return }
        // Never disturb a gesture in progress; the end of the gesture renders again.
        if scrollView.isZooming || scrollView.isZoomBouncing { return }

        if selectionChanged || fitRequested || naturalSize == .zero { measure() }

        if autoFit {
            applyFit()
            return
        }
        if abs(scale - renderedScale) > 0.0005 || selectionChanged {
            let focus = pendingFocus ?? (selectionChanged ? nil : visibleCenterInNatural())
            pendingFocus = nil
            render(at: scale)
            centerContent(resetOffset: selectionChanged && focus == nil)
            if let focus { scroll(toNatural: focus) }
        } else {
            host.rootView = rootView(scale: renderedScale)   // refresh content, same geometry
        }
    }

    // MARK: Measure and render

    private func rootView(scale: Double) -> AnyView {
        AnyView(ScaledCanvas(scale: scale, content: content)
            .environment(model)
            .environment(\.colorScheme, .dark))
    }

    private func measure() {
        measurer.rootView = AnyView(content.fixedSize()
            .environment(model)
            .environment(\.colorScheme, .dark))
        let size = measurer.sizeThatFits(in: CGSize(width: 100_000, height: 100_000))
        if size.width > 1, size.height > 1 {
            naturalSize = size
        }
    }

    private func clamp(_ scale: Double) -> Double {
        min(max(scale, PanelModel.scaleRange.lowerBound), PanelModel.scaleRange.upperBound)
    }

    /// Lays the panel out at `scale` with no transform, and sizes the scrollable area to it.
    private func render(at scale: Double) {
        guard naturalSize.width > 0 else { return }
        let target = clamp(scale)
        renderedScale = target
        host.rootView = rootView(scale: target)
        if scrollView.zoomScale != 1 { scrollView.zoomScale = 1 }
        let size = CGSize(width: (naturalSize.width * target).rounded(.up),
                          height: (naturalSize.height * target).rounded(.up))
        host.view.frame = CGRect(origin: .zero, size: size)
        scrollView.contentSize = size
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        updateZoomLimits()
    }

    /// Native pinch limits, relative to the scale currently rendered: down to the whole page,
    /// up to the model's maximum.
    private func updateZoomLimits() {
        guard renderedScale > 0 else { return }
        let lowest = min(wholePageScale() ?? PanelModel.scaleRange.lowerBound, PanelModel.scaleRange.upperBound)
        let highest = max(PanelModel.scaleRange.upperBound, lowest)
        scrollView.minimumZoomScale = CGFloat(lowest / renderedScale)
        scrollView.maximumZoomScale = CGFloat(highest / renderedScale)
    }

    // MARK: Fit

    /// Fill the width when that leaves little to scroll vertically; otherwise show the whole page.
    private func fitScale() -> Double? {
        let bounds = scrollView.bounds.size
        guard naturalSize.width > 0, naturalSize.height > 0, bounds.width > 0, bounds.height > 0 else { return nil }
        let availableWidth = bounds.width - margin * 2
        let availableHeight = bounds.height - margin * 2
        let byWidth = availableWidth / naturalSize.width
        let byHeight = availableHeight / naturalSize.height
        let heightAtWidthFit = naturalSize.height * byWidth
        let scale = heightAtWidthFit <= availableHeight * 1.35 ? byWidth : min(byWidth, byHeight)
        return clamp(Double(scale))
    }

    /// Scale at which the whole page is visible.
    private func wholePageScale() -> Double? {
        let bounds = scrollView.bounds.size
        guard naturalSize.width > 0, naturalSize.height > 0, bounds.width > 0, bounds.height > 0 else { return nil }
        return clamp(Double(min((bounds.width - margin * 2) / naturalSize.width,
                                (bounds.height - margin * 2) / naturalSize.height)))
    }

    private func applyFit() {
        guard let fit = fitScale() else { return }
        if abs(fit - renderedScale) > 0.001 || host.view.frame.size == .zero {
            render(at: fit)
        } else {
            host.rootView = rootView(scale: renderedScale)
            updateZoomLimits()
        }
        centerContent(resetOffset: true)
        if abs(model.canvasScale - fit) > 0.002 {
            let model = self.model
            Task { @MainActor in model.setScale(fit) }
        }
    }

    // MARK: Position

    /// Centres an axis that fits the screen; keeps a margin on an axis that does not.
    private func centerContent(resetOffset: Bool) {
        let content = scrollView.contentSize
        let bounds = scrollView.bounds.size
        let horizontal = max((bounds.width - content.width) / 2, margin)
        let vertical = max((bounds.height - content.height) / 2, margin)
        let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
        if scrollView.contentInset != inset { scrollView.contentInset = inset }
        let fitsWidth = content.width + inset.left + inset.right <= bounds.width + 0.5
        let fitsHeight = content.height + inset.top + inset.bottom <= bounds.height + 0.5
        var offset = scrollView.contentOffset
        if resetOffset || fitsWidth { offset.x = -inset.left }
        if resetOffset || fitsHeight { offset.y = -inset.top }
        if offset != scrollView.contentOffset { scrollView.contentOffset = offset }
    }

    /// Point of the panel (natural units) at the centre of the screen.
    private func visibleCenterInNatural() -> CGPoint? {
        guard renderedScale > 0 else { return nil }
        let factor = CGFloat(renderedScale) * scrollView.zoomScale
        return CGPoint(x: (scrollView.contentOffset.x + scrollView.bounds.width / 2) / factor,
                       y: (scrollView.contentOffset.y + scrollView.bounds.height / 2) / factor)
    }

    /// Scrolls so that a panel point (natural units) sits at the centre, within the scroll limits.
    private func scroll(toNatural point: CGPoint) {
        let factor = CGFloat(renderedScale) * scrollView.zoomScale
        let inset = scrollView.contentInset
        let bounds = scrollView.bounds.size
        let content = scrollView.contentSize
        var x = point.x * factor - bounds.width / 2
        var y = point.y * factor - bounds.height / 2
        x = min(max(x, -inset.left), max(content.width + inset.right - bounds.width, -inset.left))
        y = min(max(y, -inset.top), max(content.height + inset.bottom - bounds.height, -inset.top))
        scrollView.contentOffset = CGPoint(x: x, y: y)
    }

    // MARK: Gestures

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        host.view
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerContent(resetOffset: false)
    }

    /// Commit the pinch: re-render at the new scale (sharp) and drop the transform, keeping the
    /// panel exactly where it is on screen.
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        let newScale = clamp(renderedScale * Double(scale))
        let offset = scrollView.contentOffset
        render(at: newScale)
        centerContent(resetOffset: false)
        scrollView.contentOffset = offset
        centerContent(resetOffset: false)
        if let fit = fitScale(), abs(newScale - fit) < 0.01 {
            model.requestFit()          // pinched back to fit: keep following the screen size
        } else {
            model.pinch(to: newScale)   // manual zoom: stop refitting
        }
    }

    /// Two-finger tap: from fit, zoom to touch size around the tapped point; otherwise back to fit.
    @objc private func handleTwoFingerTap(_ gesture: UITapGestureRecognizer) {
        if model.autoFit, let fit = fitScale(), renderedScale > 0 {
            let location = gesture.location(in: host.view)   // host coordinates, zoom is 1 here
            pendingFocus = CGPoint(x: location.x / CGFloat(renderedScale), y: location.y / CGFloat(renderedScale))
            model.pinch(to: max(touchScale, fit * 1.8))
        } else {
            model.requestFit()
        }
    }
}

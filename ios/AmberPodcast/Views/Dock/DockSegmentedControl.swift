import UIKit

/// A vertical icon + title cell rendered inside a dock segment.
/// Two instances exist per tab: a base (inactive colour) and an accent (active colour)
/// copy that is masked to the liquid-lens indicator, which is what makes the label
/// change colour exactly where the glass passes over it.
@available(iOS 26.0, *)
final class DockItemView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()

    init(icon: String, title: String) {
        super.init(frame: .zero)
        isUserInteractionEnabled = false

        let configuration = UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)
        iconView.image = UIImage(systemName: icon, withConfiguration: configuration)
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .vertical)

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [iconView, titleLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize { CGSize(width: 68, height: 40) }

    func apply(tint: UIColor) {
        iconView.tintColor = tint
        titleLabel.textColor = tint
    }
}

/// UIKit dock modelled on the iOS 26 tab bar.
///
/// The interactive glass "bubble" on touch down is only available to `UITabBar`
/// and `UISegmentedControl`, so this control is built on the latter and hides all
/// of its stock chrome. The internal liquid-lens indicator is tracked every frame
/// via `CADisplayLink` so accent colouring follows the glass rather than the
/// selection state.
@available(iOS 26.0, *)
final class DockSegmentedControl: UISegmentedControl {
    struct Item {
        let icon: String
        let title: String
    }

    var activeTint: UIColor = .white
    var inactiveTint: UIColor = .secondaryLabel
    /// Fired only on touch up, matching native tab bar commit semantics.
    var onSelect: ((Int) -> Void)?

    private var baseViews: [DockItemView] = []
    private var accentViews: [DockItemView] = []
    private var displayLink: CADisplayLink?
    private var proxy: DisplayLinkProxy?
    private var lastIndicatorRect: CGRect = .zero
    private var stableFrames = 0
    private var originalIndex: Int?
    private weak var cachedIndicator: UIView?

    #if DEBUG
    private var traceSamples: [CGFloat] = []
    private var traceEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-amberTraceIndicator")
    }
    #endif

    private static let baseTag = 7_001
    private static let accentTag = 7_002
    private static let stableFrameThreshold = 3

    init(items: [Item]) {
        super.init(items: items.map { _ in "" })
        backgroundColor = .clear
        selectedSegmentTintColor = .clear
        setBackgroundImage(UIImage(), for: .normal, barMetrics: .default)
        setBackgroundImage(UIImage(), for: .selected, barMetrics: .default)
        setDividerImage(UIImage(), forLeftSegmentState: .normal, rightSegmentState: .normal, barMetrics: .default)

        baseViews = items.map { DockItemView(icon: $0.icon, title: $0.title) }
        accentViews = items.map { DockItemView(icon: $0.icon, title: $0.title) }
        baseViews.forEach { $0.apply(tint: inactiveTint) }
        accentViews.forEach { $0.apply(tint: activeTint) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLink?.isPaused = false
        stableFrames = 0
        hideStockChrome()
        injectItemViewsIfNeeded()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopDisplayLink() } else { startDisplayLink() }
    }

    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        hideStockChrome()
    }

    private func hideStockChrome() {
        func walk(_ view: UIView) {
            for subview in view.subviews {
                if subview is UIImageView {
                    subview.alpha = 0
                }
                if let label = subview as? UILabel,
                   label.superview?.tag != Self.baseTag,
                   label.superview?.tag != Self.accentTag {
                    label.isHidden = true
                }
                walk(subview)
            }
        }
        walk(self)
    }

    private func segmentViews() -> [UIView] {
        var result: [UIView] = []
        func walk(_ view: UIView) {
            for subview in view.subviews {
                if String(describing: type(of: subview)) == "UISegment" {
                    result.append(subview)
                } else {
                    walk(subview)
                }
            }
        }
        walk(self)
        return result.sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    private func injectItemViewsIfNeeded() {
        let segments = segmentViews()
        guard segments.count == baseViews.count else { return }

        for (index, segment) in segments.enumerated() {
            if segment.viewWithTag(Self.baseTag) == nil {
                attach(baseViews[index], to: segment, tag: Self.baseTag)
            }
            if segment.viewWithTag(Self.accentTag) == nil {
                let accent = accentViews[index]
                attach(accent, to: segment, tag: Self.accentTag)
                let mask = CAShapeLayer()
                mask.path = UIBezierPath(rect: .zero).cgPath
                accent.layer.mask = mask
            }
        }
    }

    private func attach(_ item: DockItemView, to segment: UIView, tag: Int) {
        item.tag = tag
        item.translatesAutoresizingMaskIntoConstraints = false
        segment.addSubview(item)
        NSLayoutConstraint.activate([
            item.centerXAnchor.constraint(equalTo: segment.centerXAnchor),
            item.centerYAnchor.constraint(equalTo: segment.centerYAnchor),
        ])
    }

    // MARK: - Indicator tracking

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let proxy = DisplayLinkProxy(control: self)
        self.proxy = proxy
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
        proxy = nil
    }

    private func findIndicatorView() -> UIView? {
        var stack: [UIView] = [self]
        while let view = stack.popLast() {
            if String(describing: type(of: view)) == "_UILiquidLensView" { return view }
            stack.append(contentsOf: view.subviews)
        }
        return nil
    }

    private func currentIndicatorRect() -> CGRect {
        if cachedIndicator == nil { cachedIndicator = findIndicatorView() }
        if let indicator = cachedIndicator {
            let indicatorLayer = indicator.layer.presentation() ?? indicator.layer
            let selfLayer = layer.presentation() ?? layer
            return selfLayer.convert(indicatorLayer.bounds, from: indicatorLayer)
        }
        let segments = segmentViews()
        guard selectedSegmentIndex >= 0, selectedSegmentIndex < segments.count else { return .zero }
        return segments[selectedSegmentIndex].frame
    }

    fileprivate func updateMasks() {
        let indicatorRect = currentIndicatorRect()

        if indicatorRect == lastIndicatorRect {
            stableFrames += 1
            if stableFrames >= Self.stableFrameThreshold {
                displayLink?.isPaused = true
                #if DEBUG
                flushTraceIfNeeded()
                #endif
                return
            }
        } else {
            stableFrames = 0
            lastIndicatorRect = indicatorRect
        }

        #if DEBUG
        if traceEnabled, traceSamples.last != indicatorRect.minX {
            traceSamples.append(indicatorRect.minX)
        }
        #endif

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in baseViews.indices {
            applyMasks(index: index, indicatorRect: indicatorRect)
        }
        CATransaction.commit()
    }

    private func applyMasks(index: Int, indicatorRect: CGRect) {
        guard index < accentViews.count, index < baseViews.count else { return }
        let base = baseViews[index]
        let accent = accentViews[index]

        let accentLayer = accent.layer.presentation() ?? accent.layer
        let selfLayer = layer.presentation() ?? layer
        let viewRect = selfLayer.convert(accentLayer.bounds, from: accentLayer)

        let local = CGRect(
            x: indicatorRect.minX - viewRect.minX,
            y: indicatorRect.minY - viewRect.minY,
            width: indicatorRect.width,
            height: indicatorRect.height
        )
        let capsule = UIBezierPath(roundedRect: local, cornerRadius: indicatorRect.height / 2)

        let accentMask = (accent.layer.mask as? CAShapeLayer) ?? {
            let mask = CAShapeLayer()
            accent.layer.mask = mask
            return mask
        }()
        accentMask.path = capsule.cgPath

        if indicatorRect.intersects(viewRect) {
            let baseMask = (base.layer.mask as? CAShapeLayer) ?? {
                let mask = CAShapeLayer()
                base.layer.mask = mask
                return mask
            }()
            let path = UIBezierPath(rect: base.bounds)
            path.append(capsule)
            baseMask.fillRule = .evenOdd
            baseMask.path = path.cgPath
        } else {
            base.layer.mask = nil
        }
    }

    #if DEBUG
    /// Writes the observed indicator x positions to Documents so CI can prove the
    /// lens travelled through intermediate positions instead of snapping.
    private func flushTraceIfNeeded() {
        guard traceEnabled, !traceSamples.isEmpty else { return }
        let line = traceSamples.map { String(format: "%.1f", $0) }.joined(separator: ",")
        traceSamples.removeAll()
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = dir.appendingPathComponent("indicator_trace.txt")
        let payload = (line + "\n").data(using: .utf8) ?? Data()
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(payload)
            try? handle.close()
        } else {
            try? payload.write(to: url)
        }
    }
    #endif

    // MARK: - Touch handling

    private func index(at point: CGPoint) -> Int {
        guard numberOfSegments > 0 else { return 0 }
        let width = bounds.width / CGFloat(numberOfSegments)
        return min(max(Int(point.x / width), 0), numberOfSegments - 1)
    }

    private var movesIndicatorOnTouchDown: Bool {
        !traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return super.touchesBegan(touches, with: event) }
        displayLink?.isPaused = false
        stableFrames = 0
        if movesIndicatorOnTouchDown {
            originalIndex = selectedSegmentIndex
            selectedSegmentIndex = index(at: touch.location(in: self))
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return super.touchesMoved(touches, with: event) }
        displayLink?.isPaused = false
        stableFrames = 0
        if movesIndicatorOnTouchDown {
            let target = index(at: touch.location(in: self))
            if target != selectedSegmentIndex { selectedSegmentIndex = target }
        }
        super.touchesMoved(touches, with: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        displayLink?.isPaused = false
        stableFrames = 0
        if movesIndicatorOnTouchDown, let originalIndex {
            if selectedSegmentIndex != originalIndex { onSelect?(selectedSegmentIndex) }
        }
        originalIndex = nil
        super.touchesEnded(touches, with: event)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        displayLink?.isPaused = false
        stableFrames = 0
        if movesIndicatorOnTouchDown, let originalIndex {
            selectedSegmentIndex = originalIndex
        }
        originalIndex = nil
        super.touchesCancelled(touches, with: event)
    }
}

@available(iOS 26.0, *)
@MainActor
private final class DisplayLinkProxy: NSObject {
    weak var control: DockSegmentedControl?

    init(control: DockSegmentedControl) {
        self.control = control
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let control else {
            link.invalidate()
            return
        }
        control.updateMasks()
    }
}

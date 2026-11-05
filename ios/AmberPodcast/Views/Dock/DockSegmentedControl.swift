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

        let configuration = UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
        iconView.image = UIImage(systemName: icon, withConfiguration: configuration)
        iconView.contentMode = .scaleAspectFit
        iconView.setContentHuggingPriority(.required, for: .vertical)

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
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
            iconView.heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(iconTint: UIColor, labelTint: UIColor) {
        iconView.tintColor = iconTint
        titleLabel.textColor = labelTint
    }
}

/// Self-drawn glass dock.
///
/// Earlier revisions subclassed `UISegmentedControl` to borrow its private liquid
/// lens, but UIKit stopped exposing the internal `UISegment` views on iOS 26, so
/// no item views were ever injected and the bar rendered blank. Everything here is
/// own geometry: even segment frames, a `UIGlassEffect` capsule that springs
/// between segments, and accent item views masked to that capsule so label colour
/// changes exactly where the glass passes over it.
@available(iOS 26.0, *)
final class DockSegmentedControl: UIView {
    struct Item {
        let icon: String
        let title: String
    }

    var onSelect: ((Int) -> Void)?
    /// Reports the pressed item (nil when the touch ends) so the host can float a
    /// glass bubble above the bar.
    var onTouchChanged: ((Int?) -> Void)?

    var activeTint: UIColor = .white { didSet { applyTints() } }
    var inactiveTint: UIColor = .secondaryLabel { didSet { applyTints() } }

    private(set) var items: [Item] = []
    private var baseViews: [DockItemView] = []
    private var accentViews: [DockItemView] = []

    private let lens = UIVisualEffectView(effect: UIGlassEffect())
    private let selectionFeedback = UISelectionFeedbackGenerator()

    private var displayLink: CADisplayLink?
    private var proxy: DisplayLinkProxy?
    private var lastLensRect: CGRect = .null
    private var stableFrames = 0
    private var pressedIndex: Int?
    private var originalIndex: Int?

    private static let lensInset: CGFloat = 4
    private static let stableFrameThreshold = 3

    var numberOfSegments: Int { items.count }

    var selectedSegmentIndex: Int = 0 {
        didSet {
            guard oldValue != selectedSegmentIndex else { return }
            moveLens(to: selectedSegmentIndex, animated: true)
        }
    }

    init(items: [Item]) {
        super.init(frame: .zero)
        backgroundColor = .clear
        lens.isUserInteractionEnabled = false
        lens.clipsToBounds = true
        // A faint white lift so the lens reads as a raised pill over the graphite bar.
        let lift = UIView()
        lift.backgroundColor = UIColor(white: 1, alpha: 0.06)
        lift.frame = lens.bounds
        lift.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        lens.contentView.addSubview(lift)
        lens.layer.cornerCurve = .continuous
        addSubview(lens)
        setItems(items)
    }

    convenience init(items: [AmberDockItem]) {
        self.init(items: items.map { Item(icon: $0.icon, title: $0.title) })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Items

    private func setItems(_ newItems: [Item]) {
        baseViews.forEach { $0.removeFromSuperview() }
        accentViews.forEach { $0.removeFromSuperview() }
        items = newItems
        baseViews = newItems.map { DockItemView(icon: $0.icon, title: $0.title) }
        accentViews = newItems.map { DockItemView(icon: $0.icon, title: $0.title) }
        for view in baseViews + accentViews { insertSubview(view, aboveSubview: lens) }
        applyTints()
        setNeedsLayout()
    }

    func sync(items newItems: [AmberDockItem], selectedIndex: Int) {
        let mapped = newItems.map { Item(icon: $0.icon, title: $0.title) }
        let changed = mapped.count != items.count
            || zip(mapped, items).contains { $0.icon != $1.icon || $0.title != $1.title }
        if changed { setItems(mapped) }

        let clamped = min(max(selectedIndex, 0), max(numberOfSegments - 1, 0))
        if clamped != selectedSegmentIndex { selectedSegmentIndex = clamped }
        resumeIndicatorTracking()
    }

    private func applyTints() {
        baseViews.forEach { $0.apply(iconTint: inactiveTint, labelTint: inactiveTint) }
        accentViews.forEach { $0.apply(iconTint: .white, labelTint: activeTint) }
    }

    func resumeIndicatorTracking() {
        displayLink?.isPaused = false
        stableFrames = 0
        lastLensRect = .null
    }

    // MARK: - Geometry

    private func segmentRect(_ index: Int) -> CGRect {
        let count = max(numberOfSegments, 1)
        let width = bounds.width / CGFloat(count)
        return CGRect(x: width * CGFloat(index), y: 0, width: width, height: bounds.height)
    }

    func lensFrame(for index: Int) -> CGRect {
        segmentRect(index).insetBy(dx: Self.lensInset, dy: Self.lensInset)
    }

    /// Centre x of the given item in control coordinates.
    func centerX(for index: Int) -> CGFloat? {
        guard index >= 0, index < numberOfSegments else { return nil }
        return segmentRect(index).midX
    }

    func segmentCentersInSelf() -> [CGPoint] {
        (0..<numberOfSegments).map { CGPoint(x: segmentRect($0).midX, y: bounds.midY) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for (index, view) in baseViews.enumerated() {
            view.frame = segmentRect(index)
            accentViews[index].frame = segmentRect(index)
        }
        let lensHeight = max(bounds.height - Self.lensInset * 2, 1)
        lens.layer.cornerRadius = lensHeight / 2
        lens.frame = lensFrame(for: min(max(selectedSegmentIndex, 0), max(numberOfSegments - 1, 0)))
        resumeIndicatorTracking()
        updateMasks()
    }

    private func moveLens(to index: Int, animated: Bool) {
        guard index >= 0, index < numberOfSegments else { return }
        resumeIndicatorTracking()
        let target = lensFrame(for: index)
        guard animated else {
            lens.frame = target
            updateMasks()
            return
        }
        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.84,
            initialSpringVelocity: 0.25,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.lens.frame = target
        }
    }

    // MARK: - Lens tracking

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopDisplayLink() } else { startDisplayLink() }
    }

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

    fileprivate func updateMasks() {
        let lensLayer = lens.layer.presentation() ?? lens.layer
        let rect = layer.convert(lensLayer.bounds, from: lensLayer)

        if rect == lastLensRect {
            stableFrames += 1
            if stableFrames >= Self.stableFrameThreshold {
                displayLink?.isPaused = true
                return
            }
        } else {
            stableFrames = 0
            lastLensRect = rect
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in baseViews.indices { applyMasks(index: index, lensRect: rect) }
        CATransaction.commit()
    }

    private func applyMasks(index: Int, lensRect: CGRect) {
        guard index < accentViews.count, index < baseViews.count else { return }
        let base = baseViews[index]
        let accent = accentViews[index]

        let local = lensRect.intersection(base.frame)
            .offsetBy(dx: -base.frame.minX, dy: -base.frame.minY)
        let capsule = UIBezierPath(roundedRect: local, cornerRadius: lensRect.height / 2)

        let accentMask = (accent.layer.mask as? CAShapeLayer) ?? {
            let mask = CAShapeLayer()
            accent.layer.mask = mask
            return mask
        }()
        accentMask.path = capsule.cgPath

        if lensRect.intersects(base.frame) {
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

    // MARK: - Touch handling

    private func index(at point: CGPoint) -> Int {
        guard numberOfSegments > 0 else { return 0 }
        let width = bounds.width / CGFloat(numberOfSegments)
        return min(max(Int(point.x / width), 0), numberOfSegments - 1)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let index = index(at: touch.location(in: self))
        originalIndex = selectedSegmentIndex
        pressedIndex = index
        selectionFeedback.prepare()
        if index != selectedSegmentIndex {
            selectionFeedback.selectionChanged()
            selectedSegmentIndex = index
        }
        onTouchChanged?(index)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let index = index(at: touch.location(in: self))
        guard index != pressedIndex else { return }
        pressedIndex = index
        selectionFeedback.selectionChanged()
        selectedSegmentIndex = index
        onTouchChanged?(index)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let pressed = pressedIndex else { return }
        pressedIndex = nil
        onTouchChanged?(nil)
        if let originalIndex, pressed != originalIndex { onSelect?(pressed) }
        self.originalIndex = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        pressedIndex = nil
        onTouchChanged?(nil)
        if let originalIndex {
            selectedSegmentIndex = originalIndex
            self.originalIndex = nil
        }
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

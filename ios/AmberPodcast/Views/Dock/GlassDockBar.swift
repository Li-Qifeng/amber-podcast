import SwiftUI
import UIKit

/// A wide, lifted glass dock that keeps the native segmented lens and adds a
/// compact floating bubble above the touched item. The bubble lives in its own
/// non-clipping overlay so `UIGlassEffect` sizing never inflates it.
@available(iOS 26.0, *)
struct GlassDockBar: UIViewRepresentable {
    let items: [AmberDockItem]
    @Binding var selectedIndex: Int

    func makeUIView(context: Context) -> DockContainerView {
        DockContainerView(items: items) { selectedIndex = $0 }
    }

    func updateUIView(_ uiView: DockContainerView, context: Context) {
        uiView.sync(items: items, selectedIndex: selectedIndex)
    }
}

@available(iOS 26.0, *)
@MainActor
final class DockContainerView: UIView {
    private let control: DockSegmentedControl
    private let barGlassView = UIVisualEffectView(effect: UIGlassEffect())
    private let bubbleGlassView = UIVisualEffectView(effect: UIGlassEffect())

    private let barHeight: CGFloat = 60
    private let bubbleHeight: CGFloat = 42
    private let bubbleTopPadding: CGFloat = 6

    private var hideTimer: Timer?

    init(items: [AmberDockItem], onSelect: @escaping (Int) -> Void) {
        control = DockSegmentedControl(items: items)
        super.init(frame: .zero)

        control.onSelect = onSelect
        control.onTouchChanged = { [weak self] index in
            self?.showBubble(for: index)
        }

        barGlassView.isUserInteractionEnabled = false
        barGlassView.layer.cornerCurve = .continuous
        barGlassView.clipsToBounds = true
        addSubview(barGlassView)

        control.translatesAutoresizingMaskIntoConstraints = false
        addSubview(control)

        bubbleGlassView.isUserInteractionEnabled = false
        bubbleGlassView.alpha = 0
        bubbleGlassView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        bubbleGlassView.layer.cornerCurve = .continuous
        bubbleGlassView.clipsToBounds = true
        addSubview(bubbleGlassView)

        NSLayoutConstraint.activate([
            control.leadingAnchor.constraint(equalTo: leadingAnchor),
            control.trailingAnchor.constraint(equalTo: trailingAnchor),
            control.bottomAnchor.constraint(equalTo: bottomAnchor),
            control.heightAnchor.constraint(equalToConstant: barHeight),

            barGlassView.leadingAnchor.constraint(equalTo: control.leadingAnchor),
            barGlassView.trailingAnchor.constraint(equalTo: control.trailingAnchor),
            barGlassView.topAnchor.constraint(equalTo: control.topAnchor),
            barGlassView.bottomAnchor.constraint(equalTo: control.bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func sync(items: [AmberDockItem], selectedIndex: Int) {
        control.sync(items: items, selectedIndex: selectedIndex)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        barGlassView.cornerConfiguration = .capsule()
        bubbleGlassView.layer.cornerRadius = bubbleGlassView.bounds.height / 2
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: barHeight + bubbleHeight + bubbleTopPadding)
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let barFrame = control.frame.insetBy(dx: -12, dy: -12)
        return barFrame.contains(point) ? control : nil
    }

    #if DEBUG
    private var didShowDemoBubble = false
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, ProcessInfo.processInfo.arguments.contains("-amberDemoBubble"), !didShowDemoBubble {
            didShowDemoBubble = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
                self?.showBubble(for: 1)
            }
        }
    }
    #endif

    private func showBubble(for index: Int?) {
        hideTimer?.invalidate()
        guard let index else {
            UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.bubbleGlassView.alpha = 0
                self.bubbleGlassView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            }
            return
        }

        let centers = control.segmentCentersInSelf()
        guard index >= 0, index < centers.count else { return }

        let bubbleWidth = max(64, min(104, (bounds.width / CGFloat(max(control.numberOfSegments, 1))) - 18))
        bubbleGlassView.bounds = CGRect(x: 0, y: 0, width: bubbleWidth, height: bubbleHeight)
        bubbleGlassView.center = CGPoint(
            x: control.frame.minX + centers[index].x,
            y: bubbleHeight / 2
        )

        UIView.animate(withDuration: 0.28, delay: 0, usingSpringWithDamping: 0.72, initialSpringVelocity: 0.2,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.bubbleGlassView.alpha = 1
            self.bubbleGlassView.transform = .identity
        }

        // Auto-hide after a beat so it doesn't linger over content.
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.showBubble(for: nil) }
        }
    }
}

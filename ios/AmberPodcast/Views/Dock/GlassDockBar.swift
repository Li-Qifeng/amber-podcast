import SwiftUI
import UIKit

/// A wide, lifted dock bar. Geometry follows the Apple media-app standard:
/// ~90% screen width, 60pt tall, floating clear of the home indicator.
///
/// The bar itself is a graphite surface rather than a glass panel — `UIGlassEffect`
/// over a pure-black canvas refracts nothing and reads as flat grey, so depth comes
/// from a surface step plus the real glass lens travelling between items.
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
    /// Transparent strip above the bar that the bubble rises into.
    static let bubbleHeadroom: CGFloat = 26
    static let barHeight: CGFloat = 60

    private let control: DockSegmentedControl
    private let barSurface = UIView()
    private let bubble = UIView()

    private var hideTimer: Timer?

    init(items: [AmberDockItem], onSelect: @escaping (Int) -> Void) {
        control = DockSegmentedControl(items: items)
        super.init(frame: .zero)

        control.onSelect = onSelect
        control.onTouchChanged = { [weak self] index in
            self?.showBubble(for: index)
        }

        barSurface.backgroundColor = UIColor(white: 0.09, alpha: 0.92)
        barSurface.layer.cornerCurve = .continuous
        barSurface.layer.borderWidth = 0.5
        barSurface.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        barSurface.layer.shadowColor = UIColor.black.cgColor
        barSurface.layer.shadowOpacity = 0.35
        barSurface.layer.shadowRadius = 16
        barSurface.layer.shadowOffset = CGSize(width: 0, height: 8)
        barSurface.isUserInteractionEnabled = false
        addSubview(barSurface)

        addSubview(control)

        bubble.backgroundColor = UIColor(white: 0.16, alpha: 0.96)
        bubble.layer.borderWidth = 0.5
        bubble.layer.borderColor = UIColor(white: 1, alpha: 0.16).cgColor
        bubble.layer.shadowColor = UIColor.black.cgColor
        bubble.layer.shadowOpacity = 0.4
        bubble.layer.shadowRadius = 12
        bubble.layer.shadowOffset = CGSize(width: 0, height: 6)
        bubble.isUserInteractionEnabled = false
        bubble.alpha = 0
        bubble.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        addSubview(bubble)
    }

    required init?(coder: NSCoder) { fatalError() }

    func sync(items: [AmberDockItem], selectedIndex: Int) {
        control.sync(items: items, selectedIndex: selectedIndex)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let barRect = CGRect(
            x: 0,
            y: bounds.height - Self.barHeight,
            width: bounds.width,
            height: Self.barHeight
        )
        barSurface.frame = barRect
        barSurface.layer.cornerRadius = Self.barHeight / 2
        barSurface.layer.shadowPath = UIBezierPath(
            roundedRect: barRect,
            cornerRadius: Self.barHeight / 2
        ).cgPath
        control.frame = barRect
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard control.frame.insetBy(dx: -8, dy: -8).contains(point) else { return nil }
        return super.hitTest(point, with: event)
    }

    #if DEBUG
    private var didShowDemoBubble = false
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil,
              ProcessInfo.processInfo.arguments.contains("-amberDemoBubble"),
              !didShowDemoBubble else { return }
        didShowDemoBubble = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.showBubble(for: 1)
        }
    }
    #endif

    private func showBubble(for index: Int?) {
        hideTimer?.invalidate()

        guard let index,
              let centerX = control.centerX(for: index) else {
            UIView.animate(
                withDuration: 0.16,
                delay: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.bubble.alpha = 0
                self.bubble.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
            }
            return
        }

        let itemWidth = bounds.width / CGFloat(max(control.numberOfSegments, 1))
        let size = CGSize(width: min(itemWidth - 16, 96), height: 42)
        bubble.transform = .identity
        bubble.frame = CGRect(
            x: centerX - size.width / 2,
            y: bounds.height - Self.barHeight - size.height + 14,
            width: size.width,
            height: size.height
        )
        bubble.layer.cornerRadius = size.height / 2
        bubble.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)

        UIView.animate(
            withDuration: 0.34,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.3,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.bubble.alpha = 1
            self.bubble.transform = .identity
        }

        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.showBubble(for: nil) }
        }
    }
}

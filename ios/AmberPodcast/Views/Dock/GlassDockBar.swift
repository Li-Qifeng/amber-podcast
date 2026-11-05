import SwiftUI
import UIKit

/// One entry in the floating dock.
struct AmberDockItem: Hashable {
    let icon: String
    let title: String
}

/// Assembles the glass dock: a `UIGlassContainerEffect` hosts a `UIGlassEffect`
/// capsule that wraps the segmented control, so the bar and any future sibling
/// (mini player) can blend into one field.
@available(iOS 26.0, *)
final class GlassDockBarView: UIView {
    let containerEffectView: UIVisualEffectView
    let barGlassView: UIVisualEffectView
    let control: DockSegmentedControl

    private let contentPadding: CGFloat = 2
    private let containerSpacing: CGFloat = 8
    private let bubbleSize = CGSize(width: 64, height: 64)
    private let bubbleView = UIVisualEffectView(effect: UIGlassEffect())

    init(items: [AmberDockItem], selectedIndex: Int, onSelect: @escaping (Int) -> Void) {
        let containerEffect = UIGlassContainerEffect()
        containerEffect.spacing = containerSpacing
        containerEffectView = UIVisualEffectView(effect: containerEffect)

        let glassEffect = UIGlassEffect()
        glassEffect.isInteractive = true
        barGlassView = UIVisualEffectView(effect: glassEffect)

        control = DockSegmentedControl(items: items.map { .init(icon: $0.icon, title: $0.title) })
        control.selectedSegmentIndex = selectedIndex
        control.activeTint = UIColor(AmberTheme.primaryAmber)
        control.inactiveTint = UIColor(AmberTheme.labelTertiary)
        control.onSelect = onSelect

        bubbleView.isUserInteractionEnabled = false
        bubbleView.alpha = 0
        bubbleView.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
        bubbleView.layer.cornerRadius = bubbleSize.height / 2
        bubbleView.layer.cornerCurve = .continuous
        bubbleView.clipsToBounds = true
        addSubview(bubbleView)

        control.onTouchChanged = { [weak self] index in
            self?.showBubble(for: index)
        }

        super.init(frame: .zero)

        addSubview(containerEffectView)
        containerEffectView.translatesAutoresizingMaskIntoConstraints = false
        containerEffectView.contentView.addSubview(barGlassView)
        barGlassView.translatesAutoresizingMaskIntoConstraints = false
        barGlassView.contentView.addSubview(control)
        control.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            containerEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerEffectView.topAnchor.constraint(equalTo: topAnchor),
            containerEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            barGlassView.leadingAnchor.constraint(equalTo: containerEffectView.contentView.leadingAnchor),
            barGlassView.trailingAnchor.constraint(equalTo: containerEffectView.contentView.trailingAnchor),
            barGlassView.topAnchor.constraint(equalTo: containerEffectView.contentView.topAnchor),
            barGlassView.bottomAnchor.constraint(equalTo: containerEffectView.contentView.bottomAnchor),

            control.leadingAnchor.constraint(equalTo: barGlassView.contentView.leadingAnchor, constant: contentPadding),
            control.trailingAnchor.constraint(equalTo: barGlassView.contentView.trailingAnchor, constant: -contentPadding),
            control.topAnchor.constraint(equalTo: barGlassView.contentView.topAnchor, constant: contentPadding),
            control.bottomAnchor.constraint(equalTo: barGlassView.contentView.bottomAnchor, constant: -contentPadding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        barGlassView.cornerConfiguration = .capsule()
        bubbleView.cornerConfiguration = .capsule()
    }

    /// Floats a glass bubble above the touched item, mimicking the native tab bar.
    private func showBubble(for index: Int?) {
        guard let index, let centerX = control.centerX(for: index) else {
            UIView.animate(
                withDuration: 0.18,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0,
                options: [.beginFromCurrentState, .allowUserInteraction]
            ) {
                self.bubbleView.alpha = 0
                self.bubbleView.transform = CGAffineTransform(scaleX: 0.4, y: 0.4)
            }
            return
        }

        bubbleView.frame = CGRect(
            x: centerX - bubbleSize.width / 2,
            y: -bubbleSize.height + 14,
            width: bubbleSize.width,
            height: bubbleSize.height
        )

        UIView.animate(
            withDuration: 0.32,
            delay: 0,
            usingSpringWithDamping: 0.62,
            initialSpringVelocity: 0.4,
            options: [.beginFromCurrentState, .allowUserInteraction]
        ) {
            self.bubbleView.alpha = 1
            self.bubbleView.transform = .identity
        }
    }

    func setSelectedIndex(_ index: Int) {
        guard index != control.selectedSegmentIndex else { return }
        control.selectedSegmentIndex = index
        control.resumeIndicatorTracking()
    }
}

/// SwiftUI bridge for the UIKit glass dock. Only used on iOS 26+; earlier systems
/// keep the existing SwiftUI dock through `AmberTabBarRendering`.
@available(iOS 26.0, *)
struct GlassDockBar: UIViewRepresentable {
    let items: [AmberDockItem]
    @Binding var selectedIndex: Int

    func makeUIView(context: Context) -> GlassDockBarView {
        GlassDockBarView(items: items, selectedIndex: selectedIndex) { index in
            selectedIndex = index
        }
    }

    func updateUIView(_ view: GlassDockBarView, context: Context) {
        view.setSelectedIndex(selectedIndex)
    }
}

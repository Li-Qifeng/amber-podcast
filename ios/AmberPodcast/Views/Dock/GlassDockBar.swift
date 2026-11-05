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
    }

    func setSelectedIndex(_ index: Int) {
        guard index != control.selectedSegmentIndex else { return }
        control.selectedSegmentIndex = index
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

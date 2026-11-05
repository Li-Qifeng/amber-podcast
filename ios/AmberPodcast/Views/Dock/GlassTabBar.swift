import SwiftUI
import UIKit

/// Native glass tab bar. Unlike the segmented-control dock, `UITabBar` gets the
/// real iOS 26 treatment: a floating glass capsule plus the bubble that lifts off
/// the bar around the touched item.
@available(iOS 26.0, *)
final class GlassTabBarView: UIView, UITabBarDelegate {
    /// Enlarges the whole native bar; the system capsule itself has a fixed size.
    static let capsuleScale: CGFloat = 1.14

    let tabBar = UITabBar()
    var onSelect: ((Int) -> Void)?

    private var suppressCallback = false

    init(items: [AmberDockItem], selectedIndex: Int, onSelect: @escaping (Int) -> Void) {
        self.onSelect = onSelect
        super.init(frame: .zero)

        tabBar.delegate = self
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        tabBar.items = items.enumerated().map { index, item in
            UITabBarItem(
                title: item.title,
                image: UIImage(
                    systemName: item.icon,
                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
                ),
                tag: index
            )
        }
        tabBar.selectedItem = tabBar.items?[min(selectedIndex, max(items.count - 1, 0))]
        configureAppearance()
        tabBar.transform = CGAffineTransform(scaleX: Self.capsuleScale, y: Self.capsuleScale)
        addSubview(tabBar)
        NSLayoutConstraint.activate([
            tabBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            tabBar.topAnchor.constraint(equalTo: topAnchor),
            tabBar.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureAppearance() {
        let appearance = UITabBarAppearance()
        // Keep the system Liquid Glass background; only override the item colours.
        appearance.configureWithDefaultBackground()

        let item = UITabBarItemAppearance()
        item.normal.iconColor = UIColor(AmberTheme.labelTertiary)
        item.normal.titleTextAttributes = [
            .foregroundColor: UIColor(AmberTheme.labelTertiary),
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
        ]
        item.selected.iconColor = .white
        item.selected.titleTextAttributes = [
            .foregroundColor: UIColor(AmberTheme.primaryAmber),
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold),
        ]
        // The iOS 26 capsule only ever reserves ~48pt, so the stacked icon and
        // title collide; nudge the title down to keep a visible gap.
        let titleOffset = UIOffset(horizontal: 0, vertical: 6)
        item.normal.titlePositionAdjustment = titleOffset
        item.selected.titlePositionAdjustment = titleOffset
        item.focused.titlePositionAdjustment = titleOffset

        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        // The iOS 26 bar hugs its items, so widen each item to reach the target
        // 92%-of-screen capsule instead of a cramped 63% one.
        tabBar.itemPositioning = .centered
        appearance.stackedItemWidth = 120
        appearance.stackedItemPositioning = .centered
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.isTranslucent = true
        tabBar.backgroundColor = .clear
    }

    func setSelectedIndex(_ index: Int) {
        guard let items = tabBar.items, index >= 0, index < items.count else { return }
        guard tabBar.selectedItem !== items[index] else { return }
        suppressCallback = true
        tabBar.selectedItem = items[index]
        suppressCallback = false
    }

    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
        guard !suppressCallback else { return }
        onSelect?(item.tag)
    }
}

@available(iOS 26.0, *)
struct GlassTabBar: UIViewRepresentable {
    let items: [AmberDockItem]
    @Binding var selectedIndex: Int

    func makeUIView(context: Context) -> GlassTabBarView {
        GlassTabBarView(items: items, selectedIndex: selectedIndex) { index in
            selectedIndex = index
        }
    }

    func updateUIView(_ view: GlassTabBarView, context: Context) {
        view.setSelectedIndex(selectedIndex)
    }
}

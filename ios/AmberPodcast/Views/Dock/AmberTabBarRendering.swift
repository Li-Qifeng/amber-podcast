import SwiftUI
import UIKit

/// Single seam for the floating dock, mirroring Rex's `RexTabBarRendering`:
/// iOS 26+ gets the UIKit glass bar (native touch-down bubble and liquid-lens
/// indicator), everything older keeps the SwiftUI implementation.
enum AmberTabBarRendering {
    @ViewBuilder
    static func dock(
        items: [AmberDockItem],
        selection: Binding<Int>,
        isCollapsed: Bool = false,
        width: CGFloat,
        height: CGFloat
    ) -> some View {
        LegacyDockBar(
            items: items,
            selection: selection,
            isCollapsed: isCollapsed,
            width: isCollapsed ? 152 : width,
            height: isCollapsed ? 48 : height
        )
    }
}

/// SwiftUI fallback for systems without the iOS 26 glass tab bar.
struct LegacyDockBar: View {
    let items: [AmberDockItem]
    @Binding var selection: Int
    var isCollapsed: Bool = false
    let width: CGFloat
    let height: CGFloat

    @Namespace private var indicatorNamespace
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        HStack(spacing: 0) {
            if isCollapsed {
                if items.indices.contains(0) {
                    collapsedItemView(index: 0, item: items[0])
                }
                if items.indices.contains(2) {
                    collapsedItemView(index: 2, item: items[2])
                }
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    itemView(index: index, item: item)
                }
            }
        }
        .padding(4)
        .frame(width: width, height: height)
        .amberGlass(.capsule, isInteractive: true)
        .animation(ForwardMotion.fluidSheet, value: isCollapsed)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !isCollapsed else { return }
                    let itemWidth = width / CGFloat(max(items.count, 1))
                    let index = min(items.count - 1, max(0, Int(value.location.x / itemWidth)))
                    guard index != selection else { return }
                    impact.impactOccurred(intensity: 0.6)
                    withAnimation(ForwardMotion.mercuryTab) {
                        selection = index
                    }
                }
        )
    }

    private func collapsedItemView(index: Int, item: AmberDockItem) -> some View {
        let isSelected = selection == index

        return Button {
            impact.impactOccurred()
            withAnimation(ForwardMotion.mercuryTab) {
                selection = index
            }
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .amberGlass(.capsule, tint: AmberTheme.primaryAmber.opacity(0.10))
                        .matchedGeometryEffect(id: "activeDockIndicator", in: indicatorNamespace)
                }

                HStack(spacing: 4) {
                    Image(systemName: item.icon)
                        .font(.system(size: 15, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AmberTheme.labelPrimary : AmberTheme.labelTertiary)

                    Text(item.title)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? AmberTheme.primaryAmber : AmberTheme.labelTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func itemView(index: Int, item: AmberDockItem) -> some View {
        let isSelected = selection == index

        return Button {
            impact.impactOccurred()
            withAnimation(ForwardMotion.mercuryTab) {
                selection = index
            }
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .amberGlass(.capsule, tint: AmberTheme.primaryAmber.opacity(0.07))
                        .matchedGeometryEffect(id: "activeDockIndicator", in: indicatorNamespace)
                }

                VStack(spacing: 3) {
                    Image(systemName: item.icon)
                        .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AmberTheme.labelPrimary : AmberTheme.labelTertiary)
                        .scaleEffect(isSelected ? 1.04 : 1.0)

                    Text(item.title)
                        .font(.system(size: 10, weight: isSelected ? .medium : .regular, design: .rounded))
                        .foregroundStyle(isSelected ? AmberTheme.primaryAmber : AmberTheme.labelTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

// MARK: - Surface Primitives
//
// Rex splits its design system into material primitives (`CellPlate`,
// `SubtleSurfaceView`, `MaterialBackdropView`) instead of letting every view
// assemble its own background, border and shadow. These are the Amber
// equivalents: two primitives cover the two cases the app actually has.
//
// - `amberPlate`       : solid content surface — list rows, section cards.
// - `amberMediaCard`   : clipped artwork surface — covers, 16:9 stills.

/// Solid surface with a quiet hairline. `isActive` promotes the hairline to the
/// accent so the playing row reads without a filled tint.
public struct AmberPlateModifier: ViewModifier {
    public var radius: CGFloat
    public var isActive: Bool

    public func body(content: Content) -> some View {
        content
            .background(
                AmberTheme.surfaceCard,
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        isActive ? AmberTheme.primaryAmber.opacity(0.35) : AmberTheme.borderHairline,
                        lineWidth: 0.5
                    )
            )
    }
}

/// Media surface: clips the artwork to a squircle and adds a neutral (never
/// coloured) shadow for depth.
///
/// No strokeBorder: on artwork the 0.5pt hairline reads as a hard "box" around
/// every cover. Apple's own artwork tiles are borderless — the clip shape plus
/// shadow already separates them from the canvas.
public struct AmberMediaCardModifier: ViewModifier {
    public var radius: CGFloat

    public func body(content: Content) -> some View {
        content
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: Color.black.opacity(0.30), radius: 6, y: 3)
    }
}

public extension View {
    func amberPlate(
        radius: CGFloat = AmberTheme.radiusCardRow,
        isActive: Bool = false
    ) -> some View {
        modifier(AmberPlateModifier(radius: radius, isActive: isActive))
    }

    func amberMediaCard(
        radius: CGFloat = AmberTheme.radiusCardShelf
    ) -> some View {
        modifier(AmberMediaCardModifier(radius: radius))
    }

    /// 去掉导航栏那条厚重的毛玻璃，但把 iOS 26 原生的 scrollEdgeEffect 留下来。
    /// 滚动时状态栏区域会自然浮现一层轻模糊（时间/电量始终可读），大标题按系统
    /// 标准节奏收缩 —— 这是 Apple HIG 的默认行为，也是"不生硬"的来源。
    /// 上一版把 scrollEdgeEffect 一起关掉，导致标题收缩后完全悬空，观感很硬。
    @ViewBuilder
    func amberImmersiveTopEdge() -> some View {
        if #available(iOS 26.0, *) {
            self
                .scrollEdgeEffectStyle(.soft, for: .top)
                .toolbarBackground(.hidden, for: .navigationBar)
        } else {
            self.toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    /// 统一的返回按钮：纯箭头，不依赖上一页标题。
    /// 三个 Tab 根页面的 navigationTitle 是空的（标题自绘在 leading），
    /// 系统返回按钮拿不到文字会退化成 "..."，所以子页面必须自带返回按钮。
    func amberBackButton() -> some View {
        modifier(AmberBackButtonModifier())
    }
}

public struct AmberBackButtonModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    public func body(content: Content) -> some View {
        content
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AmberTheme.labelPrimary)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                }
            }
    }
}

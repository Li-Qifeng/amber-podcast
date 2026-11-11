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
}

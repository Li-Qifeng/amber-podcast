import SwiftUI
import UIKit

// MARK: - ==========================================
// MARK: 1. Design Tokens: Graphite Neutral Ramp & Quiet Accent
// MARK: - ==========================================

public enum AmberTheme {
    // Canvas & Surface: OLED True Black + Graphite Neutral Ramp (Unslop Standard)
    public static let background = Color(red: 0.0, green: 0.0, blue: 0.0)             // Deepest #000000
    public static let surfaceDeep = Color(red: 0.05, green: 0.05, blue: 0.06)          // Surface #0d0d0f
    public static let surfaceCard = Color(red: 0.09, green: 0.09, blue: 0.10)          // Surface #17171a
    public static let surfaceRaised = Color(red: 0.14, green: 0.14, blue: 0.15)        // Raised #232326
    
    // Legacy Glass Surfaces (Quiet & Translucent)
    public static let glassSurface = Color(white: 0.12).opacity(0.50)
    public static let glassSurfaceElevated = Color(white: 0.18).opacity(0.65)
    public static let glassHighlight = Color.white.opacity(0.15)

    // Precise Hi-Fi Accent (Used Rarely: ~2-3% of Screen Area)
    public static let primaryAmber = Color(red: 0.96, green: 0.62, blue: 0.04)         // Amber Gold #F59E0B
    public static let accentElectric = Color(red: 0.20, green: 0.78, blue: 0.35)       // Electric Green #32C759
    
    // Strict 3-Role Text Hierarchy (Graphite Tinted)
    public static let labelPrimary = Color(red: 0.95, green: 0.95, blue: 0.96)         // Primary #f2f2f5
    public static let labelSecondary = Color(red: 0.60, green: 0.60, blue: 0.64)       // Secondary #9a9aa2
    public static let labelTertiary = Color(red: 0.45, green: 0.45, blue: 0.48)        // Muted #72727a
    public static let labelQuaternary = Color(red: 0.28, green: 0.28, blue: 0.31)      // Faint #47474f

    // Quiet Hairline Border (6% to 10% White Opacity - Never Neon)
    public static let borderHairline = Color.white.opacity(0.08)
    public static let borderSpecular = Color.white.opacity(0.14)

    // Strict Nested Squircle Radius Scale (Nested Radius: Outer - Padding = Inner)
    public static let radiusControl: CGFloat = 8.0          // Controls, small buttons, tags
    public static let radiusBadge: CGFloat = 6.0            // Micro badges, keycaps, time tags
    public static let radiusCardRow: CGFloat = 12.0         // List row cards
    public static let radiusCardShelf: CGFloat = 14.0       // 16:9 Shelf cards
    public static let radiusCoverHero: CGFloat = 18.0       // Hero media artwork
    public static let radiusDock: CGFloat = 28.0            // Floating Dock (Physical Capsule)
    
    // 4px Spacing Grid System & Screen Proportions
    public static let pageMargin: CGFloat = 16.0            // 16 pt edge margin
    public static let cardGap: CGFloat = 12.0               // 12 pt card gap
    public static let heroBannerRatio: CGFloat = 0.58       // 58% Screen Height (Balanced, non-suffocating)
    public static let cardShelfWidthRatio: CGFloat = 0.56   // 56% Screen Width
    public static let cardShelfAspectRatio: CGFloat = 16.0 / 9.0 // 16:9 Landscape
    public static let dockWidthRatio: CGFloat = 0.90        // 90% Screen Width
    public static let dockHeight: CGFloat = 56.0            // 56 pt
    public static let dockBottomGap: CGFloat = 28.0         // 28 pt Home Bar clearance

    // Motion Springs
    public static let quickSpring = Animation.spring(response: 0.20, dampingFraction: 0.88)
    public static let fluidSpring = Animation.spring(response: 0.32, dampingFraction: 0.82)
    public static let bouncySpring = Animation.spring(response: 0.36, dampingFraction: 0.80)
}

// MARK: - ==========================================
// MARK: 2. 120Hz ProMotion Motion System (Purposeful, Non-Bouncy)
// MARK: - ==========================================

public enum ForwardMotion {
    public static let touchDown = Animation.spring(response: 0.14, dampingFraction: 0.94)
    public static let touchUp   = Animation.spring(response: 0.24, dampingFraction: 0.84)
    public static let fluidSheet = Animation.spring(response: 0.34, dampingFraction: 0.80)
    public static let snapSpring = Animation.interactiveSpring(response: 0.28, dampingFraction: 0.86)
    public static let spring     = Animation.spring(response: 0.30, dampingFraction: 0.84)
    public static let mercuryTab = Animation.spring(response: 0.26, dampingFraction: 0.82)
}

// MARK: - ==========================================
// MARK: 3. Quiet Optics: Precision Bevel & Hairline Border
// MARK: - ==========================================

/// Precision Rim Border: Simulates a crisp, machined chamfer with subtle key light
public struct LiquidGlassBorder: View {
    public var cornerRadius: CGFloat
    public var isCapsule: Bool = false
    public var lineWidth: CGFloat = 0.5
    public var isPressed: Bool = false
    public var specularCenter: UnitPoint = .topLeading

    public init(
        cornerRadius: CGFloat = AmberTheme.radiusCardShelf,
        isCapsule: Bool = false,
        lineWidth: CGFloat = 0.5,
        isPressed: Bool = false,
        specularCenter: UnitPoint = .topLeading
    ) {
        self.cornerRadius = cornerRadius
        self.isCapsule = isCapsule
        self.lineWidth = lineWidth
        self.isPressed = isPressed
        self.specularCenter = specularCenter
    }

    private var activeLineWidth: CGFloat {
        isPressed ? max(0.75, lineWidth * 1.3) : lineWidth
    }

    private var rimGradient: LinearGradient {
        if isPressed {
            let pressedColors: [Color] = [
                Color.white.opacity(0.32),
                Color.white.opacity(0.14),
                Color.white.opacity(0.04),
                Color.white.opacity(0.10)
            ]
            return LinearGradient(colors: pressedColors, startPoint: specularCenter, endPoint: .bottomTrailing)
        } else {
            let normalColors: [Color] = [
                Color.white.opacity(0.18), // Crisp top-left key incidence
                Color.white.opacity(0.08),
                Color.white.opacity(0.02), // Bottom-right shadow edge
                Color.white.opacity(0.06)
            ]
            return LinearGradient(colors: normalColors, startPoint: specularCenter, endPoint: .bottomTrailing)
        }
    }

    public var body: some View {
        Group {
            if isCapsule {
                Capsule()
                    .strokeBorder(rimGradient, lineWidth: activeLineWidth)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(rimGradient, lineWidth: activeLineWidth)
            }
        }
    }
}

/// Unified Graphite Surface: Ultra-Thin Material + Neutral Raised Tone (No Neon Glare)
public struct LiquidGlassBackground: View {
    public var cornerRadius: CGFloat
    public var isCapsule: Bool = false
    public var tint: Color? = nil
    public var isPressed: Bool = false

    public init(
        cornerRadius: CGFloat = AmberTheme.radiusCardShelf,
        isCapsule: Bool = false,
        tint: Color? = nil,
        isPressed: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.isCapsule = isCapsule
        self.tint = tint
        self.isPressed = isPressed
    }

    private var surfaceColor: Color {
        if let tint = tint {
            return tint.opacity(isPressed ? 0.20 : 0.10)
        } else {
            return isPressed ? AmberTheme.surfaceRaised : AmberTheme.surfaceCard
        }
    }

    public var body: some View {
        ZStack {
            if isCapsule {
                Capsule()
                    .fill(.ultraThinMaterial)
                Capsule()
                    .fill(surfaceColor)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(surfaceColor)
            }
        }
    }
}

// MARK: - ==========================================
// MARK: 4. Native Liquid Glass Modifiers
// MARK: - ==========================================

public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = AmberTheme.radiusCardShelf
    public var tint: Color? = nil
    public var isPressed: Bool = false

    @ViewBuilder
    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                AmberGlassMaterial.make(tint: tint, isInteractive: false),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            let shadowColor = Color.black.opacity(isPressed ? 0.18 : 0.32)
            let shadowRadius: CGFloat = isPressed ? 4.0 : 12.0
            let shadowY: CGFloat = isPressed ? 2.0 : 6.0

            content
                .background(
                    LiquidGlassBackground(cornerRadius: cornerRadius, isCapsule: false, tint: tint, isPressed: isPressed)
                )
                .overlay(
                    LiquidGlassBorder(cornerRadius: cornerRadius, isCapsule: false, lineWidth: 0.5, isPressed: isPressed)
                )
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        }
    }
}

public struct LiquidGlassCapsuleModifier: ViewModifier {
    public var tint: Color? = nil
    public var isPressed: Bool = false
    public var isInteractive: Bool = false

    @ViewBuilder
    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(
                AmberGlassMaterial.make(tint: tint, isInteractive: isInteractive),
                in: Capsule()
            )
        } else {
            let shadowColor = Color.black.opacity(isPressed ? 0.22 : 0.38)
            let shadowRadius: CGFloat = isPressed ? 5.0 : 16.0
            let shadowY: CGFloat = isPressed ? 2.0 : 8.0

            content
                .background(
                    LiquidGlassBackground(cornerRadius: 0, isCapsule: true, tint: tint, isPressed: isPressed)
                )
                .overlay(
                    LiquidGlassBorder(cornerRadius: 0, isCapsule: true, lineWidth: 0.5, isPressed: isPressed)
                )
                .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
        }
    }
}

// MARK: - ==========================================
// MARK: 5. High-Level Hi-Fi Components
// MARK: - ==========================================

public struct LiquidGlassCard<Content: View>: View {
    public var cornerRadius: CGFloat
    public var tint: Color?
    public var isPressed: Bool
    public let content: () -> Content

    public init(
        cornerRadius: CGFloat = AmberTheme.radiusCardShelf,
        tint: Color? = nil,
        isPressed: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.isPressed = isPressed
        self.content = content
    }

    public var body: some View {
        content()
            .modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, tint: tint, isPressed: isPressed))
    }
}

public struct LiquidGlassCapsule<Content: View>: View {
    public var tint: Color?
    public var isPressed: Bool
    public let content: () -> Content

    public init(
        tint: Color? = nil,
        isPressed: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.tint = tint
        self.isPressed = isPressed
        self.content = content
    }

    public var body: some View {
        content()
            .modifier(LiquidGlassCapsuleModifier(tint: tint, isPressed: isPressed))
    }
}

// MARK: - Native Tactile ButtonStyle (Subtle 0.97 Press Scale, No Overshoot)
public struct TactileButtonStyle: ButtonStyle {
    public var scale: CGFloat = 0.97
    public var enableHaptic: Bool = true
    private let impact = UIImpactFeedbackGenerator(style: .light)

    public init(scale: CGFloat = 0.97, enableHaptic: Bool = true) {
        self.scale = scale
        self.enableHaptic = enableHaptic
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(
                configuration.isPressed ? ForwardMotion.touchDown : ForwardMotion.touchUp,
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed && enableHaptic {
                    impact.prepare()
                    impact.impactOccurred()
                }
            }
    }
}

// MARK: - Native Liquid Glass ButtonStyle
public struct LiquidGlassButtonStyle: ButtonStyle {
    public var tint: Color? = nil
    public var isCapsule: Bool = false
    public var cornerRadius: CGFloat = AmberTheme.radiusControl
    private let impact = UIImpactFeedbackGenerator(style: .light)

    public init(tint: Color? = nil, isCapsule: Bool = false, cornerRadius: CGFloat = AmberTheme.radiusControl) {
        self.tint = tint
        self.isCapsule = isCapsule
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        let shadowColor = Color.black.opacity(isPressed ? 0.15 : 0.25)
        let shadowRadius: CGFloat = isPressed ? 3.0 : 8.0
        let shadowY: CGFloat = isPressed ? 1.0 : 4.0

        return configuration.label
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .background(
                LiquidGlassBackground(cornerRadius: cornerRadius, isCapsule: isCapsule, tint: tint, isPressed: isPressed)
            )
            .overlay(
                LiquidGlassBorder(
                    cornerRadius: cornerRadius,
                    isCapsule: isCapsule,
                    lineWidth: 0.5,
                    isPressed: isPressed
                )
            )
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
            .animation(isPressed ? ForwardMotion.touchDown : ForwardMotion.touchUp, value: isPressed)
            .onChange(of: isPressed) { pressed in
                if pressed {
                    impact.prepare()
                    impact.impactOccurred()
                }
            }
    }
}

// MARK: - Lightweight Card Modifier (GPU Friendly)
public struct LightweightCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = AmberTheme.radiusCardRow
    public var tint: Color? = nil
    public var isPressed: Bool = false

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint?.opacity(isPressed ? 0.16 : 0.08) ?? (isPressed ? AmberTheme.surfaceRaised : AmberTheme.surfaceCard))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isPressed ? Color.white.opacity(0.14) : AmberTheme.borderHairline, lineWidth: 0.5)
            )
    }
}

// MARK: - ButtonStyle Extension
public extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle()
    }
    static func liquidGlass(tint: Color? = nil, isCapsule: Bool = false, cornerRadius: CGFloat = AmberTheme.radiusControl) -> LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(tint: tint, isCapsule: isCapsule, cornerRadius: cornerRadius)
    }
}

public extension ButtonStyle where Self == TactileButtonStyle {
    static var tactile: TactileButtonStyle {
        TactileButtonStyle()
    }
    static func tactile(scale: CGFloat = 0.97, enableHaptic: Bool = true) -> TactileButtonStyle {
        TactileButtonStyle(scale: scale, enableHaptic: enableHaptic)
    }
}

// MARK: - View Extensions
public extension View {
    func tactileButton(scale: CGFloat = 0.97, enableHaptic: Bool = true) -> some View {
        self.buttonStyle(TactileButtonStyle(scale: scale, enableHaptic: enableHaptic))
    }

    func lightweightCard(cornerRadius: CGFloat = AmberTheme.radiusCardRow, tint: Color? = nil, isPressed: Bool = false) -> some View {
        self.modifier(LightweightCardModifier(cornerRadius: cornerRadius, tint: tint, isPressed: isPressed))
    }

    @ViewBuilder
    func amberPressable(scale: CGFloat = 0.97, action: (() -> Void)? = nil) -> some View {
        if let action = action {
            Button(action: action) {
                self
            }
            .buttonStyle(TactileButtonStyle(scale: scale))
        } else {
            self.buttonStyle(TactileButtonStyle(scale: scale))
        }
    }
    
    func frostedGlassCard(cornerRadius: CGFloat = AmberTheme.radiusCardShelf, isPressed: Bool = false) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, isPressed: isPressed))
    }
    
    func liquidGlassCard(cornerRadius: CGFloat = AmberTheme.radiusCardShelf, tint: Color? = nil, isPressed: Bool = false) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, tint: tint, isPressed: isPressed))
    }
    
    func liquidGlassCapsule(tint: Color? = nil, isPressed: Bool = false) -> some View {
        self.modifier(LiquidGlassCapsuleModifier(tint: tint, isPressed: isPressed))
    }
    
    @ViewBuilder
    func tactilePress(scale: CGFloat = 0.97, action: (() -> Void)? = nil) -> some View {
        if let action = action {
            Button(action: action) {
                self
            }
            .buttonStyle(TactileButtonStyle(scale: scale))
        } else {
            self.buttonStyle(TactileButtonStyle(scale: scale))
        }
    }
    
    func ambientGlow(color: Color = AmberTheme.primaryAmber, opacity: Double = 0.15, radius: CGFloat = 40) -> some View {
        self.background(
            color
                .opacity(opacity)
                .blur(radius: radius)
        )
    }
}

// MARK: - ==========================================
// MARK: 6. Apple Liquid Glass Bridge (iOS 26 real API, iOS 17 fallback)
// MARK: - ==========================================

/// Builds a system `Glass` value. Only usable on iOS 26+, where `Glass` exists.
@available(iOS 26.0, *)
public enum AmberGlassMaterial {
    public static func make(tint: Color?, isInteractive: Bool) -> Glass {
        var glass: Glass = .regular
        if let tint = tint {
            glass = glass.tint(tint)
        }
        if isInteractive {
            glass = glass.interactive()
        }
        return glass
    }
}

/// Thin wrapper over the system `GlassEffectContainer`.
/// On iOS 26+ it enables real shape blending and morphing between sibling glass views.
/// Below iOS 26 it is a plain passthrough.
public struct AmberGlassContainer<Content: View>: View {
    public var spacing: CGFloat?
    public let content: () -> Content

    public init(spacing: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    @ViewBuilder
    public var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }
}

/// Applies a real Liquid Glass effect on iOS 26+, and the graphite fallback below it.
public struct AmberGlassModifier: ViewModifier {
    public var shape: AmberGlassShape
    public var tint: Color?
    public var isInteractive: Bool

    public init(shape: AmberGlassShape, tint: Color? = nil, isInteractive: Bool = false) {
        self.shape = shape
        self.tint = tint
        self.isInteractive = isInteractive
    }

    @ViewBuilder
    public func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            switch shape {
            case .capsule:
                content.glassEffect(
                    AmberGlassMaterial.make(tint: tint, isInteractive: isInteractive),
                    in: Capsule()
                )
            case .circle:
                content.glassEffect(
                    AmberGlassMaterial.make(tint: tint, isInteractive: isInteractive),
                    in: Circle()
                )
            case .rect(let cornerRadius):
                content.glassEffect(
                    AmberGlassMaterial.make(tint: tint, isInteractive: isInteractive),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            }
        } else {
            switch shape {
            case .capsule:
                content.modifier(LiquidGlassCapsuleModifier(tint: tint))
            case .circle, .rect:
                let cornerRadius: CGFloat = {
                    if case .rect(let radius) = shape { return radius }
                    return 999
                }()
                content.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, tint: tint))
            }
        }
    }
}

public enum AmberGlassShape {
    case capsule
    case circle
    case rect(cornerRadius: CGFloat)
}

public extension View {
    func amberGlass(_ shape: AmberGlassShape = .capsule, tint: Color? = nil, isInteractive: Bool = false) -> some View {
        modifier(AmberGlassModifier(shape: shape, tint: tint, isInteractive: isInteractive))
    }
}

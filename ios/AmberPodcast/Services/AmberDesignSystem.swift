import SwiftUI
import UIKit

// MARK: - ==========================================
// MARK: 1. Apple HIG & OLED Obsidian Theme System
// MARK: - ==========================================

public enum AmberTheme {
    // Canvas: Pure OLED Obsidian Black
    public static let background = Color(red: 0.0, green: 0.0, blue: 0.0)
    public static let canvasSurface = Color(red: 0.04, green: 0.04, blue: 0.05)
    
    // Liquid Glass Surfaces
    public static let glassSurface = Color(white: 0.10).opacity(0.45)
    public static let glassSurfaceElevated = Color(white: 0.16).opacity(0.58)
    public static let glassHighlight = Color.white.opacity(0.30)
    
    // Core Brand Accents
    public static let primaryAmber = Color(red: 0.96, green: 0.62, blue: 0.04)   // Amber Gold #F59E0B
    public static let accentElectric = Color(red: 0.20, green: 0.78, blue: 0.35) // Electric Green #32C759
    public static let accentPurple = Color(red: 0.68, green: 0.42, blue: 0.98)   // Violet Glow
    
    // Typography Hierarchy (SF Pro)
    public static let labelPrimary = Color.white
    public static let labelSecondary = Color(white: 0.92, opacity: 0.72)
    public static let labelTertiary = Color(white: 0.92, opacity: 0.42)
    public static let labelQuaternary = Color(white: 0.92, opacity: 0.22)
    public static let borderSpecular = Color.white.opacity(0.12)
    
    // Legacy Motion System Aliases
    public static let quickSpring = Animation.spring(response: 0.22, dampingFraction: 0.88)
    public static let fluidSpring = Animation.spring(response: 0.36, dampingFraction: 0.82)
    public static let bouncySpring = Animation.spring(response: 0.42, dampingFraction: 0.76)

    // Concentric Squircle Geometry
    public static let radiusCoverHero: CGFloat = 22.0
    public static let radiusCardShelf: CGFloat = 16.0
    public static let radiusCardRow: CGFloat = 14.0
    public static let radiusDock: CGFloat = 30.0
    public static let radiusBadge: CGFloat = 6.0
    
    // Forward / Apple Golden Ratio Layout Constants
    public static let heroBannerRatio: CGFloat = 0.618      // 61.8% Screen Height
    public static let cardShelfWidthRatio: CGFloat = 0.575   // 57.5% Screen Width
    public static let cardShelfAspectRatio: CGFloat = 16.0 / 9.0 // 16:9 Landscape
    public static let dockWidthRatio: CGFloat = 0.910       // 91% Screen Width
    public static let dockHeight: CGFloat = 60.0            // 60 pt
    public static let dockBottomGap: CGFloat = 32.0         // 32 pt Home Bar clearance
    public static let pageMargin: CGFloat = 18.0            // 18 pt
    public static let cardGap: CGFloat = 12.0               // 12 pt
}

// MARK: - ==========================================
// MARK: 2. 120Hz ProMotion Fluid Physics
// MARK: - ==========================================

public enum ForwardMotion {
    public static let touchDown = Animation.spring(response: 0.16, dampingFraction: 0.92)
    public static let touchUp   = Animation.spring(response: 0.28, dampingFraction: 0.82)
    public static let fluidSheet = Animation.spring(response: 0.38, dampingFraction: 0.78)
    public static let snapSpring = Animation.interactiveSpring(response: 0.32, dampingFraction: 0.85)
    public static let spring     = Animation.spring(response: 0.35, dampingFraction: 0.82)
    public static let mercuryTab = Animation.spring(response: 0.30, dampingFraction: 0.80)
}

// MARK: - ==========================================
// MARK: 3. Liquid Glass Core Optics Engine
// MARK: - ==========================================

/// Multi-layer Fresnel Rim Border simulating carved glass with 45° key light incidence
public struct LiquidGlassBorder: View {
    public var cornerRadius: CGFloat
    public var isCapsule: Bool = false
    public var lineWidth: CGFloat = 0.75
    public var isPressed: Bool = false
    public var specularCenter: UnitPoint = .topLeading

    public init(
        cornerRadius: CGFloat = AmberTheme.radiusCardShelf,
        isCapsule: Bool = false,
        lineWidth: CGFloat = 0.75,
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
        isPressed ? max(1.2, lineWidth * 1.5) : lineWidth
    }

    private var rimGradient: LinearGradient {
        if isPressed {
            let pressedColors: [Color] = [
                Color.white.opacity(0.88), // Specular bloom when depressed
                Color.white.opacity(0.38),
                Color.white.opacity(0.12),
                Color.white.opacity(0.28)
            ]
            return LinearGradient(colors: pressedColors, startPoint: specularCenter, endPoint: .bottomTrailing)
        } else {
            let normalColors: [Color] = [
                Color.white.opacity(0.45), // Key ambient rim light
                Color.white.opacity(0.16),
                Color.white.opacity(0.04), // Ambient shadow boundary
                Color.white.opacity(0.14)
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

/// Unified Optical Background containing Ultra-Thin Material, Ambient Tint, and Top Specular Sheen
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

    private var tintFillColor: Color {
        if let tint = tint {
            return tint.opacity(isPressed ? 0.28 : 0.16)
        } else {
            return isCapsule ? AmberTheme.glassSurfaceElevated : AmberTheme.glassSurface
        }
    }

    private var glareGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(isPressed ? 0.22 : 0.09),
                Color.clear
            ],
            startPoint: .top,
            endPoint: .center
        )
    }

    public var body: some View {
        ZStack {
            if isCapsule {
                Capsule()
                    .fill(.ultraThinMaterial)
                Capsule()
                    .fill(tintFillColor)
                Capsule()
                    .fill(glareGradient)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tintFillColor)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(glareGradient)
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

    public func body(content: Content) -> some View {
        let shadowColor = Color.black.opacity(isPressed ? 0.22 : 0.42)
        let shadowRadius: CGFloat = isPressed ? 5.0 : 16.0
        let shadowY: CGFloat = isPressed ? 2.0 : 8.0

        return content
            .background(
                LiquidGlassBackground(cornerRadius: cornerRadius, isCapsule: false, tint: tint, isPressed: isPressed)
            )
            .overlay(
                LiquidGlassBorder(cornerRadius: cornerRadius, isCapsule: false, isPressed: isPressed)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
            .shadow(color: Color.black.opacity(isPressed ? 0.12 : 0.20), radius: isPressed ? 2 : 4, x: 0, y: isPressed ? 1 : 2)
    }
}

public struct LiquidGlassCapsuleModifier: ViewModifier {
    public var tint: Color? = nil
    public var isPressed: Bool = false

    public func body(content: Content) -> some View {
        let shadowColor = Color.black.opacity(isPressed ? 0.26 : 0.45)
        let shadowRadius: CGFloat = isPressed ? 7.0 : 20.0
        let shadowY: CGFloat = isPressed ? 3.0 : 10.0

        return content
            .background(
                LiquidGlassBackground(cornerRadius: 0, isCapsule: true, tint: tint, isPressed: isPressed)
            )
            .overlay(
                LiquidGlassBorder(cornerRadius: 0, isCapsule: true, isPressed: isPressed)
            )
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
            .shadow(color: Color.black.opacity(isPressed ? 0.15 : 0.24), radius: isPressed ? 2 : 5, x: 0, y: isPressed ? 1 : 2)
    }
}

// MARK: - ==========================================
// MARK: 5. High-Level Liquid Glass Components
// MARK: - ==========================================

/// High-level Liquid Glass Card Container
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

/// High-level Liquid Glass Capsule Container (for Tags, Island bars, Floating Controls)
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

/// Native Liquid Glass Button with 3D Depth Depress and Specular Bloom
public struct LiquidGlassButton<Label: View>: View {
    public var action: () -> Void
    public var tint: Color?
    public var isCapsule: Bool
    public var cornerRadius: CGFloat
    public let label: () -> Label

    @State private var isPressed: Bool = false
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    public init(
        action: @escaping () -> Void,
        tint: Color? = nil,
        isCapsule: Bool = true,
        cornerRadius: CGFloat = AmberTheme.radiusCardShelf,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.action = action
        self.tint = tint
        self.isCapsule = isCapsule
        self.cornerRadius = cornerRadius
        self.label = label
    }

    public var body: some View {
        Button(action: {
            impactFeedback.impactOccurred()
            action()
        }) {
            label()
        }
        .buttonStyle(
            LiquidGlassButtonStyle(tint: tint, isCapsule: isCapsule, cornerRadius: cornerRadius)
        )
    }
}

// MARK: - Native Liquid Glass ButtonStyle (3D Depth & Specular Bloom)
public struct LiquidGlassButtonStyle: ButtonStyle {
    public var tint: Color? = nil
    public var isCapsule: Bool = true
    public var cornerRadius: CGFloat = AmberTheme.radiusCardShelf
    private let impact = UIImpactFeedbackGenerator(style: .medium)

    public init(tint: Color? = nil, isCapsule: Bool = true, cornerRadius: CGFloat = AmberTheme.radiusCardShelf) {
        self.tint = tint
        self.isCapsule = isCapsule
        self.cornerRadius = cornerRadius
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        let shadowColor = Color.black.opacity(isPressed ? 0.20 : 0.35)
        let shadowRadius: CGFloat = isPressed ? 4.0 : 12.0
        let shadowY: CGFloat = isPressed ? 2.0 : 6.0
        let borderLineWidth: CGFloat = isPressed ? 1.2 : 0.75

        return configuration.label
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .background(
                LiquidGlassBackground(cornerRadius: cornerRadius, isCapsule: isCapsule, tint: tint, isPressed: isPressed)
            )
            .overlay(
                LiquidGlassBorder(
                    cornerRadius: cornerRadius,
                    isCapsule: isCapsule,
                    lineWidth: borderLineWidth,
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

// MARK: - Native Tactile ButtonStyle (Zero Scroll Interference)
public struct TactileButtonStyle: ButtonStyle {
    public var scale: CGFloat = 0.96
    public var enableHaptic: Bool = true
    private let impact = UIImpactFeedbackGenerator(style: .light)

    public init(scale: CGFloat = 0.96, enableHaptic: Bool = true) {
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

// MARK: - Lightweight Card Modifier (GPU Friendly for Lists)
public struct LightweightCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = AmberTheme.radiusCardRow
    public var tint: Color? = nil
    public var isPressed: Bool = false

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint?.opacity(isPressed ? 0.20 : 0.12) ?? Color(white: isPressed ? 0.12 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(isPressed ? Color.white.opacity(0.30) : Color.white.opacity(0.08), lineWidth: isPressed ? 0.8 : 0.5)
            )
    }
}

// MARK: - Ambient Backlight Glow
public struct AmbientBacklightGlow: ViewModifier {
    public var glowColor: Color = AmberTheme.primaryAmber
    public var opacity: Double = 0.25
    public var radius: CGFloat = 60

    public func body(content: Content) -> some View {
        content
            .background(
                glowColor
                    .blur(radius: radius)
                    .opacity(opacity)
            )
    }
}

// MARK: - ButtonStyle Extension
public extension ButtonStyle where Self == LiquidGlassButtonStyle {
    static var liquidGlass: LiquidGlassButtonStyle {
        LiquidGlassButtonStyle()
    }
    static func liquidGlass(tint: Color? = nil, isCapsule: Bool = true, cornerRadius: CGFloat = AmberTheme.radiusCardShelf) -> LiquidGlassButtonStyle {
        LiquidGlassButtonStyle(tint: tint, isCapsule: isCapsule, cornerRadius: cornerRadius)
    }
}

public extension ButtonStyle where Self == TactileButtonStyle {
    static var tactile: TactileButtonStyle {
        TactileButtonStyle()
    }
    static func tactile(scale: CGFloat = 0.96, enableHaptic: Bool = true) -> TactileButtonStyle {
        TactileButtonStyle(scale: scale, enableHaptic: enableHaptic)
    }
}

// MARK: - Convenient View Extensions
public extension View {
    func tactileButton(scale: CGFloat = 0.96, enableHaptic: Bool = true) -> some View {
        self.buttonStyle(TactileButtonStyle(scale: scale, enableHaptic: enableHaptic))
    }

    func lightweightCard(cornerRadius: CGFloat = AmberTheme.radiusCardRow, tint: Color? = nil, isPressed: Bool = false) -> some View {
        self.modifier(LightweightCardModifier(cornerRadius: cornerRadius, tint: tint, isPressed: isPressed))
    }

    @ViewBuilder
    func amberPressable(scale: CGFloat = 0.96, action: (() -> Void)? = nil) -> some View {
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
    func tactilePress(scale: CGFloat = 0.96, action: (() -> Void)? = nil) -> some View {
        if let action = action {
            Button(action: action) {
                self
            }
            .buttonStyle(TactileButtonStyle(scale: scale))
        } else {
            self.buttonStyle(TactileButtonStyle(scale: scale))
        }
    }
    
    func ambientGlow(color: Color = AmberTheme.primaryAmber, opacity: Double = 0.25, radius: CGFloat = 60) -> some View {
        self.modifier(AmbientBacklightGlow(glowColor: color, opacity: opacity, radius: radius))
    }
}

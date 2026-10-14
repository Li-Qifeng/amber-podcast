import SwiftUI

// MARK: - Apple Liquid Glass & Forward Design Tokens
public enum AmberTheme {
    // Canvas: OLED True Black
    public static let background = Color(red: 0.0, green: 0.0, blue: 0.0)
    public static let canvasSurface = Color(red: 0.04, green: 0.04, blue: 0.05)
    
    // Glass Base Surfaces
    public static let glassSurface = Color(white: 0.10).opacity(0.40)
    public static let glassSurfaceElevated = Color(white: 0.16).opacity(0.55)
    public static let glassHighlight = Color.white.opacity(0.28)
    
    // Accents
    public static let primaryAmber = Color(red: 0.96, green: 0.62, blue: 0.04) // Amber Gold #F59E0B
    public static let accentElectric = Color(red: 0.20, green: 0.78, blue: 0.35) // Electric Lime #32C759
    public static let accentPurple = Color(red: 0.68, green: 0.42, blue: 0.98)
    
    // Apple HIG Typographic Hierarchy
    public static let labelPrimary = Color.white
    public static let labelSecondary = Color(white: 0.92, opacity: 0.72)
    public static let labelTertiary = Color(white: 0.92, opacity: 0.42)
    public static let labelQuaternary = Color(white: 0.92, opacity: 0.22)
    public static let borderSpecular = Color.white.opacity(0.12)
    
    // Legacy Spring Aliases
    public static let quickSpring = Animation.spring(response: 0.22, dampingFraction: 0.88)
    public static let fluidSpring = Animation.spring(response: 0.36, dampingFraction: 0.82)
    public static let bouncySpring = Animation.spring(response: 0.42, dampingFraction: 0.76)
    
    // Concentric Squircle Radius System
    public static let radiusCoverHero: CGFloat = 22.0
    public static let radiusCardShelf: CGFloat = 16.0
    public static let radiusDock: CGFloat = 28.0
    public static let radiusBadge: CGFloat = 6.0
    
    // Exact Layout Proportions (From Forward / Rex CV Measurements)
    public static let heroBannerRatio: CGFloat = 0.618 // 61.8% Screen Height
    public static let cardShelfWidthRatio: CGFloat = 0.575 // 57.5% Screen Width
    public static let cardShelfAspectRatio: CGFloat = 16.0 / 9.0 // 16:9
    public static let dockWidthRatio: CGFloat = 0.910 // 91% Screen Width
    public static let dockHeight: CGFloat = 58.0 // 58 pt
    public static let dockBottomGap: CGFloat = 32.0 // 32 pt clearance for Home Bar
    public static let pageMargin: CGFloat = 18.0 // 18 pt
    public static let cardGap: CGFloat = 12.0 // 12 pt
}

// MARK: - Fluid Physics Motion System (120Hz ProMotion Tuned)
public enum ForwardMotion {
    public static let touchDown = Animation.spring(response: 0.18, dampingFraction: 0.92)
    public static let touchUp   = Animation.spring(response: 0.30, dampingFraction: 0.80)
    public static let fluidSheet = Animation.spring(response: 0.40, dampingFraction: 0.78)
    public static let snapSpring = Animation.interactiveSpring(response: 0.32, dampingFraction: 0.85)
}

// MARK: - Liquid Glass Specular Rim Border
public struct LiquidGlassBorder: View {
    public var cornerRadius: CGFloat
    public var isCapsule: Bool = false
    public var lineWidth: CGFloat = 0.75
    
    private var rimGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.38), // Top-left specular key light
                Color.white.opacity(0.14),
                Color.white.opacity(0.04), // Bottom-right shadow edge
                Color.white.opacity(0.10)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    public var body: some View {
        Group {
            if isCapsule {
                Capsule()
                    .strokeBorder(rimGradient, lineWidth: lineWidth)
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(rimGradient, lineWidth: lineWidth)
            }
        }
    }
}

// MARK: - Liquid Glass Modifiers
public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = AmberTheme.radiusCardShelf
    public var tint: Color? = nil

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint?.opacity(0.12) ?? AmberTheme.glassSurface)
                    
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            )
            .overlay(
                LiquidGlassBorder(cornerRadius: cornerRadius, isCapsule: false)
            )
            .shadow(color: Color.black.opacity(0.40), radius: 16, x: 0, y: 8)
            .shadow(color: Color.black.opacity(0.20), radius: 4, x: 0, y: 2)
    }
}

public struct LiquidGlassCapsuleModifier: ViewModifier {
    public var tint: Color? = nil

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Capsule()
                        .fill(tint?.opacity(0.14) ?? AmberTheme.glassSurfaceElevated)
                    
                    Capsule()
                        .fill(.ultraThinMaterial)
                }
            )
            .overlay(
                LiquidGlassBorder(cornerRadius: 0, isCapsule: true)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 20, x: 0, y: 10)
            .shadow(color: Color.black.opacity(0.25), radius: 5, x: 0, y: 2)
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
    public var cornerRadius: CGFloat = AmberTheme.radiusCardShelf
    public var tint: Color? = nil

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint?.opacity(0.15) ?? Color(white: 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
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

// MARK: - View Extensions
public extension View {
    func tactileButton(scale: CGFloat = 0.96, enableHaptic: Bool = true) -> some View {
        self.buttonStyle(TactileButtonStyle(scale: scale, enableHaptic: enableHaptic))
    }

    func lightweightCard(cornerRadius: CGFloat = AmberTheme.radiusCardShelf, tint: Color? = nil) -> some View {
        self.modifier(LightweightCardModifier(cornerRadius: cornerRadius, tint: tint))
    }

    func amberPressable(scale: CGFloat = 0.96, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            self
        }
        .buttonStyle(TactileButtonStyle(scale: scale))
    }
    
    func frostedGlassCard(cornerRadius: CGFloat = AmberTheme.radiusCardShelf) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius))
    }
    
    func liquidGlassCard(cornerRadius: CGFloat = AmberTheme.radiusCardShelf, tint: Color? = nil) -> some View {
        self.modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, tint: tint))
    }
    
    func liquidGlassCapsule(tint: Color? = nil) -> some View {
        self.modifier(LiquidGlassCapsuleModifier(tint: tint))
    }
    
    func tactilePress(scale: CGFloat = 0.96, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            self
        }
        .buttonStyle(TactileButtonStyle(scale: scale))
    }
    
    func ambientGlow(color: Color = AmberTheme.primaryAmber, opacity: Double = 0.25, radius: CGFloat = 60) -> some View {
        self.modifier(AmbientBacklightGlow(glowColor: color, opacity: opacity, radius: radius))
    }
}

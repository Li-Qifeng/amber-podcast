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

// MARK: - Liquid Glass Specular Border with Interactive Bloom & 3D Optics
public struct LiquidGlassBorder: View {
    public var cornerRadius: CGFloat
    public var isCapsule: Bool = false
    public var lineWidth: CGFloat = 0.75
    public var isPressed: Bool = false
    public var specularCenter: UnitPoint = .topLeading

    private var activeLineWidth: CGFloat {
        isPressed ? max(1.2, lineWidth * 1.5) : lineWidth
    }

    private var rimGradient: LinearGradient {
        LinearGradient(
            colors: isPressed ? [
                Color.white.opacity(0.85), // Specular bloom when pressed
                Color.white.opacity(0.35),
                Color.white.opacity(0.12),
                Color.white.opacity(0.25)
            ] : [
                Color.white.opacity(0.42), // Ambient key light
                Color.white.opacity(0.14),
                Color.white.opacity(0.04), // Ambient shadow boundary
                Color.white.opacity(0.12)
            ],
            startPoint: specularCenter,
            endPoint: .bottomTrailing
        )
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

// MARK: - Liquid Glass Modifiers (Forward & Apple Optics)
public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = AmberTheme.radiusCardShelf
    public var tint: Color? = nil
    public var isPressed: Bool = false

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Optical refraction layer
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)

                    // Ambient inner tint & refraction depth
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint?.opacity(isPressed ? 0.24 : 0.14) ?? AmberTheme.glassSurface)

                    // Specular Inner Light Bloom along top edge
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isPressed ? 0.20 : 0.08),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                LiquidGlassBorder(cornerRadius: cornerRadius, isCapsule: false, isPressed: isPressed)
            )
            // 3D Depth Physics: Drop shadow compresses into surface when pressed
            .shadow(
                color: Color.black.opacity(isPressed ? 0.25 : 0.40),
                radius: isPressed ? 6 : 16,
                x: 0,
                y: isPressed ? 2 : 8
            )
            .shadow(
                color: Color.black.opacity(isPressed ? 0.15 : 0.20),
                radius: isPressed ? 2 : 4,
                x: 0,
                y: isPressed ? 1 : 2
            )
    }
}

public struct LiquidGlassCapsuleModifier: ViewModifier {
    public var tint: Color? = nil
    public var isPressed: Bool = false

    public func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Optical refraction layer
                    Capsule()
                        .fill(.ultraThinMaterial)

                    // Ambient inner tint & chromatic luminescence
                    Capsule()
                        .fill(tint?.opacity(isPressed ? 0.26 : 0.16) ?? AmberTheme.glassSurfaceElevated)

                    // Specular Top Glare
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(isPressed ? 0.22 : 0.10),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                LiquidGlassBorder(cornerRadius: 0, isCapsule: true, isPressed: isPressed)
            )
            // 3D Depth Physics: Capsule sinks closer to background upon depression
            .shadow(
                color: Color.black.opacity(isPressed ? 0.30 : 0.45),
                radius: isPressed ? 8 : 20,
                x: 0,
                y: isPressed ? 3 : 10
            )
            .shadow(
                color: Color.black.opacity(isPressed ? 0.18 : 0.25),
                radius: isPressed ? 2 : 5,
                x: 0,
                y: isPressed ? 1 : 2
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
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .background(
                Group {
                    if isCapsule {
                        Capsule().fill(.ultraThinMaterial)
                            .overlay(Capsule().fill(configuration.isPressed ? (tint?.opacity(0.28) ?? Color.white.opacity(0.16)) : (tint?.opacity(0.12) ?? Color.white.opacity(0.04))))
                    } else {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(.ultraThinMaterial)
                            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(configuration.isPressed ? (tint?.opacity(0.28) ?? Color.white.opacity(0.16)) : (tint?.opacity(0.12) ?? Color.white.opacity(0.04))))
                    }
                }
            )
            .overlay(
                LiquidGlassBorder(
                    cornerRadius: cornerRadius,
                    isCapsule: isCapsule,
                    lineWidth: configuration.isPressed ? 1.2 : 0.75,
                    isPressed: configuration.isPressed
                )
            )
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.20 : 0.35),
                radius: configuration.isPressed ? 4 : 12,
                y: configuration.isPressed ? 2 : 6
            )
            .animation(configuration.isPressed ? ForwardMotion.touchDown : ForwardMotion.touchUp, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed {
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

// MARK: - View Extensions
public extension View {
    func tactileButton(scale: CGFloat = 0.96, enableHaptic: Bool = true) -> some View {
        self.buttonStyle(TactileButtonStyle(scale: scale, enableHaptic: enableHaptic))
    }

    func lightweightCard(cornerRadius: CGFloat = AmberTheme.radiusCardShelf, tint: Color? = nil) -> some View {
        self.modifier(LightweightCardModifier(cornerRadius: cornerRadius, tint: tint))
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

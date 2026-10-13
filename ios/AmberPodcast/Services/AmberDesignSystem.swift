import SwiftUI

// MARK: - Amber Design Tokens (Inspired by Forward / Rex & Apple HIG)
public enum AmberTheme {
    // Colors
    public static let background = Color(red: 0.0, green: 0.0, blue: 0.0) // True OLED Black
    public static let cardSurface = Color(red: 0.07, green: 0.07, blue: 0.08) // #121214
    public static let cardSurfaceElevated = Color(red: 0.11, green: 0.11, blue: 0.13) // #1C1C21
    
    // Accents
    public static let primaryAmber = Color(red: 0.96, green: 0.62, blue: 0.04) // Amber Gold #F59E0B
    public static let accentElectric = Color(red: 0.20, green: 0.78, blue: 0.35) // Forward Electric Lime #32C759
    public static let accentPurple = Color(red: 0.68, green: 0.42, blue: 0.98) // Audio track accent
    
    // Label Hierarchies
    public static let labelPrimary = Color.white
    public static let labelSecondary = Color(white: 0.92, opacity: 0.65)
    public static let labelTertiary = Color(white: 0.92, opacity: 0.35)
    public static let borderSpecular = Color.white.opacity(0.12)
    
    // Corner Radius System (Concentric hierarchy)
    public static let radiusCard: CGFloat = 20.0
    public static let radiusCover: CGFloat = 16.0
    public static let radiusPill: CGFloat = 30.0
    public static let radiusSmall: CGFloat = 8.0
    
    // Springs
    public static let fluidSpring = Animation.spring(response: 0.36, dampingFraction: 0.82)
    public static let bouncySpring = Animation.spring(response: 0.42, dampingFraction: 0.76)
    public static let quickSpring = Animation.spring(response: 0.22, dampingFraction: 0.88)
}

// MARK: - View Modifiers for Forward-style Tactile UI
public struct AmberPressableModifier: ViewModifier {
    @State private var isPressed = false
    public var scale: CGFloat = 0.96
    public var action: (() -> Void)?

    public func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? scale : 1.0)
            .animation(AmberTheme.quickSpring, value: isPressed)
            ._onButtonGesture { pressing in
                isPressed = pressing
            } perform: {
                action?()
            }
    }
}

public struct FrostedGlassCard: ViewModifier {
    public var cornerRadius: CGFloat = AmberTheme.radiusCard
    public var strokeColor: Color = AmberTheme.borderSpecular

    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color(white: 0.12).opacity(0.45))
                    .background(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(strokeColor, lineWidth: 0.5)
            )
    }
}

public extension View {
    func amberPressable(scale: CGFloat = 0.96, action: (() -> Void)? = nil) -> some View {
        self.modifier(AmberPressableModifier(scale: scale, action: action))
    }
    
    func frostedGlassCard(cornerRadius: CGFloat = AmberTheme.radiusCard) -> some View {
        self.modifier(FrostedGlassCard(cornerRadius: cornerRadius))
    }
}

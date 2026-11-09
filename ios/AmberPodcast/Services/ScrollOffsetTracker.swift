import SwiftUI

public struct ScrollOffsetPreferenceKey: PreferenceKey {
    public static var defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct IsDockCollapsedKey: EnvironmentKey {
    static let defaultValue: Binding<Bool> = .constant(false)
}

public extension EnvironmentValues {
    var isDockCollapsed: Binding<Bool> {
        get { self[IsDockCollapsedKey.self] }
        set { self[IsDockCollapsedKey.self] = newValue }
    }
}

public struct ScrollDirectionObserverModifier: ViewModifier {
    @Binding public var isCollapsed: Bool
    public var threshold: CGFloat = 3.5

    @State private var previousOffset: CGFloat = 0

    public func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScrollOffsetPreferenceKey.self,
                        value: proxy.frame(in: .named("amberScrollSpace")).minY
                    )
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { currentOffset in
                let delta = currentOffset - previousOffset
                // If user returns to top of screen, immediately restore full expanded state
                if currentOffset >= -10 && isCollapsed {
                    withAnimation(ForwardMotion.mercuryTab) {
                        isCollapsed = false
                    }
                } else if delta < -threshold && !isCollapsed && currentOffset < -30 {
                    // Scrolling down (content moving up) -> minimize dock to 2-button pill & compact player
                    withAnimation(ForwardMotion.mercuryTab) {
                        isCollapsed = true
                    }
                } else if delta > threshold && isCollapsed {
                    // Scrolling up (content moving down) -> expand dock to full 4-tab bar
                    withAnimation(ForwardMotion.mercuryTab) {
                        isCollapsed = false
                    }
                }
                previousOffset = currentOffset
            }
    }
}

public extension View {
    func trackScrollDirection(isCollapsed: Binding<Bool>, threshold: CGFloat = 3.5) -> some View {
        self.modifier(ScrollDirectionObserverModifier(isCollapsed: isCollapsed, threshold: threshold))
    }

    func amberScrollSpace() -> some View {
        self.coordinateSpace(name: "amberScrollSpace")
    }
}

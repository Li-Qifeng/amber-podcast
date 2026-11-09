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
                // 1. Returning to top of screen (within 25pt) -> Always expand full dock
                if currentOffset >= -25 {
                    if isCollapsed {
                        withAnimation(ForwardMotion.mercuryTab) {
                            isCollapsed = false
                        }
                    }
                } else if currentOffset < -50 {
                    // 2. Scrolled down past hero header -> collapse dock on downward motion
                    if currentOffset < previousOffset && !isCollapsed {
                        withAnimation(ForwardMotion.mercuryTab) {
                            isCollapsed = true
                        }
                    } else if currentOffset > previousOffset + 3.0 && isCollapsed {
                        // 3. Actively scrolling back up -> restore expanded dock
                        withAnimation(ForwardMotion.mercuryTab) {
                            isCollapsed = false
                        }
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

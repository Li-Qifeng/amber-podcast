import SwiftUI

/// Global coordinator orchestrating Apple Podcasts style Dock and MiniPlayer scroll minimization.
@MainActor
public final class AmberScrollCoordinator: ObservableObject {
    public static let shared = AmberScrollCoordinator()

    @Published public var isDockCollapsed: Bool = false

    private var lastOffset: CGFloat = 0

    private init() {}

    public func reset() {
        lastOffset = 0
        isDockCollapsed = false
    }

    public func handleOffset(_ offset: CGFloat) {
        let delta = offset - lastOffset

        // 1. Returning to top of scroll content (within 20pt) -> Always expand full dock
        if offset <= 20 {
            if isDockCollapsed {
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = false
                }
            }
        } else if offset > 50 {
            // 2. Scrolled down past header area:
            // Continuous downward scroll (delta > 2.0) -> collapse dock to bilateral wings, sink player capsule
            if delta > 2.0 && !isDockCollapsed {
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = true
                }
            } else if delta < -4.0 && isDockCollapsed {
                // Continuous upward flick (delta < -4.0) -> expand back to full dock & float player up
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = false
                }
            }
        }

        lastOffset = offset
    }

    // Fallback for probe update
    public func updateScroll(globalY: CGFloat) {}
}

public struct AmberScrollTopProbe: View {
    public init() {}
    public var body: some View {
        Color.clear.frame(height: 0)
    }
}

public extension View {
    /// Native iOS 17+ high-performance scroll observer directly listening to underlying UIScrollView contentOffset.y.
    func amberScrollObservable() -> some View {
        self.onScrollGeometryChange(for: CGFloat.self, of: { geometry in
            geometry.contentOffset.y
        }) { oldValue, newValue in
            AmberScrollCoordinator.shared.handleOffset(newValue)
        }
    }

    // Deprecated compatibility shims
    func trackScrollDirection(isCollapsed: Binding<Bool>, threshold: CGFloat = 3.5) -> some View {
        self
    }

    func amberScrollSpace() -> some View {
        self
    }
}

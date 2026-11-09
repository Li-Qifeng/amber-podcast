import SwiftUI

/// PreferenceKey capturing absolute physical screen Y position (.global) of the scroll content top anchor.
public struct AmberScrollGlobalYPreferenceKey: PreferenceKey {
    public static var defaultValue: CGFloat? = nil
    public static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() {
            value = next
        }
    }
}

/// Global coordinator orchestrating Apple Podcasts style Dock and MiniPlayer scroll minimization.
@MainActor
public final class AmberScrollCoordinator: ObservableObject {
    public static let shared = AmberScrollCoordinator()

    @Published public var isDockCollapsed: Bool = false

    private var initialTopY: CGFloat? = nil
    private var previousY: CGFloat? = nil

    private init() {}

    public func reset() {
        initialTopY = nil
        previousY = nil
        isDockCollapsed = false
    }

    public func updateScroll(globalY: CGFloat) {
        if initialTopY == nil {
            initialTopY = globalY
            previousY = globalY
            return
        }

        guard let initial = initialTopY, let prev = previousY else { return }
        let scrollDistance = initial - globalY // Scrolled down -> globalY becomes smaller -> distance > 0
        let delta = prev - globalY // Downward finger motion -> delta > 0

        // 1. Returning near top of screen (within 35pt of starting offset) -> always expand full dock
        if scrollDistance <= 35 {
            if isDockCollapsed {
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = false
                }
            }
        } else if scrollDistance > 75 {
            // 2. Scrolled past top area:
            // Continuous downward motion (delta > 2.0pt) -> collapse dock into pill
            if delta > 2.0 && !isDockCollapsed {
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = true
                }
            } else if delta < -4.0 && isDockCollapsed {
                // Continuous upward flick (delta < -4.0pt) -> expand back to full 4-tab dock
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = false
                }
            }
        }

        previousY = globalY
    }
}

/// 1pt invisible anchor placed at the very top inside ScrollView to report true physical coordinates.
public struct AmberScrollTopProbe: View {
    public init() {}

    public var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: AmberScrollGlobalYPreferenceKey.self,
                value: proxy.frame(in: .global).minY
            )
        }
        .frame(height: 1)
    }
}

public extension View {
    /// Observes top probe in physical screen coordinates and coordinates Dock/MiniPlayer minimization.
    func amberScrollObservable() -> some View {
        self.onPreferenceChange(AmberScrollGlobalYPreferenceKey.self) { y in
            if let y = y {
                AmberScrollCoordinator.shared.updateScroll(globalY: y)
            }
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

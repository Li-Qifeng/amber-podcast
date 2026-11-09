import SwiftUI

/// Global coordinator orchestrating Apple Podcasts style Dock and MiniPlayer scroll minimization.
@MainActor
public final class AmberScrollCoordinator: ObservableObject {
    public static let shared = AmberScrollCoordinator()

    @Published public var isDockCollapsed: Bool = false

    private var initialOffset: CGFloat? = nil
    private var lastOffset: CGFloat = 0
    private var accumulatedDownwardScroll: CGFloat = 0

    private init() {}

    public func reset() {
        initialOffset = nil
        lastOffset = 0
        accumulatedDownwardScroll = 0
        isDockCollapsed = false
    }

    public func handleOffset(_ offset: CGFloat) {
        if initialOffset == nil {
            initialOffset = offset
            lastOffset = offset
            return
        }

        let delta = offset - lastOffset

        // 1. Returning to top rest position -> always expand
        if let initial = initialOffset, offset <= initial + 15 {
            accumulatedDownwardScroll = 0
            if isDockCollapsed {
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = false
                }
            }
            lastOffset = offset
            return
        }

        // 2. Downward scroll -> collapse
        if delta > 1.5 {
            accumulatedDownwardScroll += delta
            if accumulatedDownwardScroll > 25 && !isDockCollapsed {
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = true
                }
            }
        } else if delta < -3.0 {
            // 3. Upward flick -> expand
            accumulatedDownwardScroll = 0
            if isDockCollapsed {
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = false
                }
            }
        }

        lastOffset = offset
    }

    public func updateScroll(globalY: CGFloat) {
        handleOffset(-globalY)
    }
}

public struct AmberScrollTopProbe: View {
    public init() {}
    public var body: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(
                    key: AmberScrollProbePreferenceKey.self,
                    value: proxy.frame(in: .global).minY
                )
        }
        .frame(height: 0)
    }
}

public struct AmberScrollProbePreferenceKey: PreferenceKey {
    public static var defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

public extension View {
    /// Native scroll observer: iOS 18+ uses onScrollGeometryChange; iOS 17 uses top probe preference key.
    @ViewBuilder
    func amberScrollObservable() -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                geometry.contentOffset.y
            }) { oldValue, newValue in
                AmberScrollCoordinator.shared.handleOffset(newValue)
            }
        } else {
            self.onPreferenceChange(AmberScrollProbePreferenceKey.self) { probeGlobalY in
                AmberScrollCoordinator.shared.updateScroll(globalY: probeGlobalY)
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

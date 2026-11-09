import SwiftUI

/// Global coordinator orchestrating Apple Podcasts style Dock and MiniPlayer scroll minimization.
@MainActor
public final class AmberScrollCoordinator: ObservableObject {
    public static let shared = AmberScrollCoordinator()

    @Published public var isDockCollapsed: Bool = false

    public private(set) var currentTab: Int = 0
    private var tabLastOffsets: [Int: CGFloat] = [:]
    private var downwardDistance: CGFloat = 0
    private var upwardDistance: CGFloat = 0

    private init() {}

    public func setTab(_ tab: Int) {
        currentTab = tab
        downwardDistance = 0
        upwardDistance = 0
        if isDockCollapsed {
            withAnimation(ForwardMotion.mercuryTab) {
                isDockCollapsed = false
            }
        }
    }

    public func reset() {
        tabLastOffsets.removeAll()
        downwardDistance = 0
        upwardDistance = 0
        if isDockCollapsed {
            withAnimation(ForwardMotion.mercuryTab) {
                isDockCollapsed = false
            }
        }
    }

    public func handleOffset(_ offset: CGFloat, forTab tab: Int? = nil) {
        let activeTab = tab ?? currentTab

        guard let last = tabLastOffsets[activeTab] else {
            // First scroll event on this tab seeds the lastOffset
            tabLastOffsets[activeTab] = offset
            return
        }

        let delta = offset - last
        tabLastOffsets[activeTab] = offset

        // Filter out sub-pixel noise
        if abs(delta) < 0.8 { return }

        if delta > 0 {
            // Scrolling down (finger moves up, content offset increases)
            downwardDistance += delta
            upwardDistance = 0
            if downwardDistance > 20 && !isDockCollapsed {
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = true
                }
            }
        } else {
            // Scrolling up (finger moves down, content offset decreases)
            upwardDistance += abs(delta)
            downwardDistance = 0
            if (upwardDistance > 12 || delta < -3.5) && isDockCollapsed {
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = false
                }
            }
        }
    }

    public func updateScroll(globalY: CGFloat, forTab tab: Int? = nil) {
        handleOffset(-globalY, forTab: tab)
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
    func amberScrollObservable(tab: Int = 0) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                geometry.contentOffset.y
            }) { oldValue, newValue in
                AmberScrollCoordinator.shared.handleOffset(newValue, forTab: tab)
            }
        } else {
            self.onPreferenceChange(AmberScrollProbePreferenceKey.self) { probeGlobalY in
                AmberScrollCoordinator.shared.handleOffset(-probeGlobalY, forTab: tab)
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

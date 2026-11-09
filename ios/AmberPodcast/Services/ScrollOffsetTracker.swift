import SwiftUI

/// Global coordinator orchestrating Apple Podcasts / Music style Dock and MiniPlayer scroll minimization.
/// Follows Apple HIG "Tab bars with an attached accessory":
/// - Minimizes into a compact 3-island inline row (active tab wing + MiniPlayer capsule + search wing) when scrolling down.
/// - Restores/expands when scrolling up intentionally, scrolling to the top, or tapping any tab.
@MainActor
public final class AmberScrollCoordinator: ObservableObject {
    public static let shared = AmberScrollCoordinator()

    @Published public var isDockCollapsed: Bool = false

    public private(set) var currentTab: Int = 0
    private var tabLastOffsets: [Int: CGFloat] = [:]
    private var tabProbeBaselines: [Int: CGFloat] = [:]
    private var downwardDistance: CGFloat = 0
    private var upwardDistance: CGFloat = 0

    // Physics parameters aligned with Apple HIG
    // Require continuous intentional movement to avoid jitter on touch lift-off or rubber-band rebound
    private let collapseScrollDownThreshold: CGFloat = 26.0  // Accumulated downward scroll to collapse
    private let expandScrollUpThreshold: CGFloat = 30.0     // Accumulated upward scroll to restore
    private let topBoundaryThreshold: CGFloat = 8.0         // If near/at top (<= 8pt), always expand

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
        if let tab = tab, tab != currentTab {
            return
        }

        // Apple HIG Rule: "A person can exit the minimized state by tapping a tab or scrolling to the top of the view."
        // When offset <= 8pt (at the top of the content, or during top overscroll bounce), always expand!
        if offset <= topBoundaryThreshold {
            downwardDistance = 0
            upwardDistance = 0
            tabLastOffsets[activeTab] = offset
            if isDockCollapsed {
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = false
                }
            }
            return
        }

        guard let last = tabLastOffsets[activeTab] else {
            tabLastOffsets[activeTab] = offset
            return
        }

        let delta = offset - last
        tabLastOffsets[activeTab] = offset

        // Ignore sub-pixel noise (touch jitter)
        if abs(delta) < 0.6 { return }

        if delta > 0 {
            // Scrolling down (finger moves up, revealing lower content)
            downwardDistance += delta
            upwardDistance = 0

            if downwardDistance >= collapseScrollDownThreshold && !isDockCollapsed {
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = true
                }
            }
        } else {
            // Scrolling up (finger moves down, revealing upper content)
            upwardDistance += abs(delta)
            downwardDistance = 0

            // Requires intentional upward scroll distance (>= 30pt),
            // completely immune to deceleration micro-rebound or touch release jitter!
            if upwardDistance >= expandScrollUpThreshold && isDockCollapsed {
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = false
                }
            }
        }
    }

    /// Fallback for iOS 17 top probe preference key
    public func handleProbeGlobalY(_ globalY: CGFloat, forTab tab: Int? = nil) {
        let activeTab = tab ?? currentTab
        if let tab = tab, tab != currentTab { return }

        if tabProbeBaselines[activeTab] == nil {
            tabProbeBaselines[activeTab] = globalY
        }
        let baseline = tabProbeBaselines[activeTab] ?? globalY
        let normalizedOffset = baseline - globalY
        handleOffset(normalizedOffset, forTab: tab)
    }

    public func updateScroll(globalY: CGFloat, forTab tab: Int? = nil) {
        handleProbeGlobalY(globalY, forTab: tab)
    }
}

public struct AmberScrollTopProbe: View {
    public let tab: Int?
    public init(tab: Int? = nil) {
        self.tab = tab
    }
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
    /// Native scroll observer: iOS 18+ uses onScrollGeometryChange with normalized visibleRect.minY; iOS 17 uses top probe preference key.
    @ViewBuilder
    func amberScrollObservable(tab: Int? = nil) -> some View {
        if #available(iOS 18.0, *) {
            self.onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                geometry.visibleRect.minY
            }) { oldValue, newValue in
                AmberScrollCoordinator.shared.handleOffset(newValue, forTab: tab)
            }
        } else {
            self.onPreferenceChange(AmberScrollProbePreferenceKey.self) { probeGlobalY in
                AmberScrollCoordinator.shared.handleProbeGlobalY(probeGlobalY, forTab: tab)
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

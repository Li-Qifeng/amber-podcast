import SwiftUI

/// Global coordinator orchestrating Apple Podcasts style Dock and MiniPlayer scroll minimization.
@MainActor
public final class AmberScrollCoordinator: ObservableObject {
    public static let shared = AmberScrollCoordinator()

    @Published public var isDockCollapsed: Bool = false

    public private(set) var currentTab: Int = 0
    private var tabBaselines: [Int: CGFloat] = [:]
    private var tabLastOffsets: [Int: CGFloat] = [:]
    private var accumulatedDownwardScroll: CGFloat = 0

    private init() {}

    public func setTab(_ tab: Int) {
        currentTab = tab
        accumulatedDownwardScroll = 0
        if isDockCollapsed {
            withAnimation(ForwardMotion.mercuryTab) {
                isDockCollapsed = false
            }
        }
    }

    public func reset() {
        tabBaselines.removeAll()
        tabLastOffsets.removeAll()
        accumulatedDownwardScroll = 0
        isDockCollapsed = false
    }

    public func handleOffset(_ offset: CGFloat, forTab tab: Int? = nil) {
        let activeTab = tab ?? currentTab

        guard let baseline = tabBaselines[activeTab] else {
            // First scroll event on this tab establishes the local baseline (whether 0 or -140)
            tabBaselines[activeTab] = offset
            tabLastOffsets[activeTab] = offset
            return
        }

        let last = tabLastOffsets[activeTab] ?? offset
        let delta = offset - last

        // 1. Returning to top rest position -> always expand
        if offset <= baseline + 15 {
            accumulatedDownwardScroll = 0
            if isDockCollapsed {
                withAnimation(ForwardMotion.mercuryTab) {
                    isDockCollapsed = false
                }
            }
            tabLastOffsets[activeTab] = offset
            return
        }

        // 2. Downward scroll -> collapse
        if delta > 1.2 {
            accumulatedDownwardScroll += delta
            if accumulatedDownwardScroll > 20 && !isDockCollapsed {
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

        tabLastOffsets[activeTab] = offset
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

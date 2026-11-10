import SwiftUI

public struct MainTabView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @ObservedObject private var scrollCoordinator = AmberScrollCoordinator.shared
    @State private var selectedTab: Int = 0
    @State private var showFullPlayer: Bool = false

    private var isDockCollapsed: Bool {
        scrollCoordinator.isDockCollapsed
    }


    #if DEBUG
    /// Stretches the tab spring so headless frame capture can see mid-transition.
    private var demoTabsSlowMotion: Bool {
        ProcessInfo.processInfo.arguments.contains("-amberSlowMotion")
    }
    #endif

    private var demoTabAnimation: Animation {
        #if DEBUG
        if demoTabsSlowMotion {
            return .spring(response: 2.0, dampingFraction: 0.82)
        }
        #endif
        return ForwardMotion.mercuryTab
    }

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background Layer: Dark Obsidian
                AmberTheme.background
                    .ignoresSafeArea()

                // Main Content Switching Layer
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()

                // Bottom Floating Island Stack: Continuous Apple Podcasts Style Sinking & Morphing
                AmberGlassContainer(spacing: 8) {
                    let fullWidth: CGFloat = min(geo.size.width - 32, 560)
                    let compactWidth: CGFloat = max(180, fullWidth - 116) // 50pt left + 8pt + 50pt right + 8pt = 116pt
                    let hasPlayer = player.currentEpisode != nil
                    let isCollapsed = isDockCollapsed && hasPlayer

                    ZStack(alignment: .bottom) {
                        // 1. Bottom Dock Level (Full 4-tab dock morphing into bilateral wings)
                        ZStack {
                            // Full 4-tab Liquid Glass Dock
                            floatingLiquidDock(geometry: geo)
                                .opacity(isCollapsed ? 0 : 1)
                                .scaleEffect(isCollapsed ? 0.96 : 1.0)
                                .allowsHitTesting(!isCollapsed)

                            // Bilateral Liquid Glass Wings (Active tab on left, Search tab on right)
                            if hasPlayer {
                                HStack(spacing: 0) {
                                    minimizedTabWing(index: selectedTab)
                                    Spacer()
                                    minimizedTabWing(index: selectedTab == 2 ? 0 : 2)
                                }
                                .frame(width: fullWidth)
                                .opacity(isCollapsed ? 1 : 0)
                                .scaleEffect(isCollapsed ? 1.0 : 0.88)
                                .allowsHitTesting(isCollapsed)
                            }
                        }
                        .frame(width: fullWidth, height: 50)

                        // 2. MiniPlayer Level (Gliding smoothly from Y = -58pt down to Y = 0, width shrinking)
                        if hasPlayer {
                            MiniPlayerView(showFullPlayer: $showFullPlayer)
                                .frame(
                                    width: isCollapsed ? compactWidth : fullWidth,
                                    height: isCollapsed ? 50 : 54
                                )
                                .offset(y: isCollapsed ? 0 : -58)
                                .onTapGesture {
                                    showFullPlayer = true
                                }
                        }
                    }
                    .frame(
                        width: fullWidth,
                        height: (hasPlayer && !isDockCollapsed) ? 112 : 50,
                        alignment: .bottom
                    )
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 8) + 6)
                .animation(ForwardMotion.fluidDockMorph, value: isDockCollapsed)
                .animation(ForwardMotion.fluidDockMorph, value: player.currentEpisode?.id)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .onChange(of: selectedTab) { newTab in
            scrollCoordinator.setTab(newTab)
        }
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView(isPresented: $showFullPlayer)
        }
        .onAppear {
            #if DEBUG
            // Launch-argument hooks so CI can screenshot a specific screen.
            if let idx = ProcessInfo.processInfo.arguments.firstIndex(of: "-amberStartTab"),
               idx + 1 < ProcessInfo.processInfo.arguments.count,
               let tab = Int(ProcessInfo.processInfo.arguments[idx + 1]) {
                selectedTab = min(max(tab, 0), 3)
            }
            if ProcessInfo.processInfo.arguments.contains("-amberOpenPlayer") {
                showFullPlayer = true
            }
            if ProcessInfo.processInfo.arguments.contains("-amberDemoTabs") {
                let interval: TimeInterval = demoTabsSlowMotion ? 4.0 : 1.5
                Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                    withAnimation(demoTabAnimation) {
                        selectedTab = (selectedTab + 1) % 4
                    }
                }
            }
            #endif
        }
    }

    // MARK: - Content View
    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case 0:
            HomeLibraryView()
        case 1:
            NativeLibraryCatalogView()
        case 2:
            SearchView()
        case 3:
            SettingsView()
        default:
            HomeLibraryView()
        }
    }

    // MARK: - Floating Dock (UIKit glass on iOS 26+, SwiftUI fallback below)
    private func minimizedTabWing(index: Int) -> some View {
        let item = dockItems[index]
        let isSelected = selectedTab == index
        return Button {
            withAnimation(ForwardMotion.fluidDockMorph) {
                scrollCoordinator.reset()
                selectedTab = index
            }
        } label: {
            Image(systemName: item.icon)
                .font(.system(size: 19, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? AmberTheme.primaryAmber : AmberTheme.labelPrimary)
                .frame(width: 50, height: 50)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .amberGlass(.circle, isInteractive: true)
        .shadow(color: Color.black.opacity(0.18), radius: 8, y: 4)
    }

    private func floatingLiquidDock(geometry: GeometryProxy) -> some View {
        let dockWidth: CGFloat = min(geometry.size.width * AmberTheme.dockWidthRatio, 420)
        let items = dockItems

        return AmberTabBarRendering.dock(
            items: items,
            selection: Binding(
                get: { selectedTab },
                set: { newIndex in
                    selectedTab = newIndex
                }
            ),
            width: dockWidth,
            height: AmberTheme.dockHeight
        )
        .onTapGesture {
            if isDockCollapsed {
                scrollCoordinator.reset()
            }
        }
    }

    private var dockItems: [AmberDockItem] {
        [
            AmberDockItem(icon: "house.fill", title: "首页"),
            AmberDockItem(icon: "square.stack.fill", title: "资料库"),
            AmberDockItem(icon: "magnifyingglass", title: "发现"),
            AmberDockItem(icon: "gearshape.fill", title: "设置"),
        ]
    }

    private var collapsedDockItems: [AmberDockItem] {
        [
            AmberDockItem(icon: "house.fill", title: "首页"),
            AmberDockItem(icon: "magnifyingglass", title: "发现"),
        ]
    }

    private func bottomClearance(for geo: GeometryProxy) -> CGFloat {
        if geo.safeAreaInsets.bottom > 0 {
            return max(10, geo.safeAreaInsets.bottom - 4)
        }
        return AmberTheme.dockBottomGap
    }
}

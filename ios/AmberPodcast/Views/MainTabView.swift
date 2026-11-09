import SwiftUI

public struct MainTabView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @ObservedObject private var scrollCoordinator = AmberScrollCoordinator.shared
    @State private var selectedTab: Int = 0
    @State private var showFullPlayer: Bool = false
    @Namespace private var dockNamespace

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

                // Bottom Floating Island Stack: Apple Podcasts Style Immersive Dock & MiniPlayer
                AmberGlassContainer(spacing: 8) {
                    if isDockCollapsed && player.currentEpisode != nil {
                        // Bilateral Collapsed Mode: Dock splits to left and right wings, MiniPlayer sinks to center
                        HStack(spacing: 8) {
                            // Leading Wing: Active Tab
                            minimizedTabWing(index: selectedTab)

                            // Center Sunk Capsule: Compact MiniPlayer
                            MiniPlayerView(showFullPlayer: $showFullPlayer)
                                .frame(width: max(geo.size.width - 128, 180))
                                .amberGlassID("miniPlayer", in: dockNamespace)
                                .transition(.scale(scale: 0.96).combined(with: .opacity))
                                .onTapGesture {
                                    showFullPlayer = true
                                }

                            // Trailing Wing: Quick Search / Settings Tab
                            minimizedTabWing(index: selectedTab == 2 ? 3 : 2)
                        }
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        // Expanded Vertical Stack Mode
                        VStack(spacing: 8) {
                            if player.currentEpisode != nil {
                                MiniPlayerView(showFullPlayer: $showFullPlayer)
                                    .frame(width: min(geo.size.width - 32, 560))
                                    .amberGlassID("miniPlayer", in: dockNamespace)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                                    .onTapGesture {
                                        showFullPlayer = true
                                    }
                            }

                            floatingLiquidDock(geometry: geo)
                        }
                    }
                }
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 8) + 6)
                .animation(ForwardMotion.mercuryTab, value: isDockCollapsed)
                .animation(ForwardMotion.mercuryTab, value: player.currentEpisode?.id)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .onChange(of: selectedTab) { _ in
            scrollCoordinator.reset()
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
        return Button {
            if isDockCollapsed {
                scrollCoordinator.reset()
            }
            selectedTab = index
        } label: {
            Image(systemName: item.icon)
                .font(.system(size: 16, weight: selectedTab == index ? .bold : .medium))
                .foregroundStyle(selectedTab == index ? AmberTheme.primaryAmber : AmberTheme.labelSecondary)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .background(
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.5)
                )
        )
        .shadow(color: Color.black.opacity(0.18), radius: 6, y: 3)
    }

    private func floatingLiquidDock(geometry: GeometryProxy) -> some View {
        let dockWidth: CGFloat = isDockCollapsed ? 152 : min(geometry.size.width * AmberTheme.dockWidthRatio, 420)
        let items = isDockCollapsed ? collapsedDockItems : dockItems

        return AmberTabBarRendering.dock(
            items: items,
            selection: Binding(
                get: {
                    if isDockCollapsed {
                        return selectedTab == 2 ? 1 : 0
                    }
                    return selectedTab
                },
                set: { newIndex in
                    if isDockCollapsed {
                        selectedTab = newIndex == 1 ? 2 : 0
                        scrollCoordinator.reset()
                    } else {
                        selectedTab = newIndex
                    }
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

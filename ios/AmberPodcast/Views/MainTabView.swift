import SwiftUI

public struct MainTabView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var selectedTab: Int = 0
    @State private var showFullPlayer: Bool = false
    @Namespace private var dockNamespace


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

                // Bottom Floating Island Stack: one shared Liquid Glass field
                AmberGlassContainer(spacing: 8) {
                    VStack(spacing: 12) {
                        if player.currentEpisode != nil {
                            MiniPlayerView(showFullPlayer: $showFullPlayer)
                                .frame(width: geo.size.width * AmberTheme.dockWidthRatio)
                                .amberGlassID("miniPlayer", in: dockNamespace)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        floatingLiquidDock(geometry: geo)
                    }
                }
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 8) + 10)
                .animation(ForwardMotion.fluidSheet, value: player.currentEpisode?.id)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView(isPresented: $showFullPlayer)
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-amberDemoTabs") {
                let interval: TimeInterval = demoTabsSlowMotion ? 4.0 : 1.5
                Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                    withAnimation(demoTabAnimation) {
                        selectedTab = (selectedTab + 1) % 3
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
            SearchView()
        case 2:
            SettingsView()
        default:
            HomeLibraryView()
        }
    }

    // MARK: - Floating Dock (UIKit glass on iOS 26+, SwiftUI fallback below)
    private func floatingLiquidDock(geometry: GeometryProxy) -> some View {
        AmberTabBarRendering.dock(
            items: dockItems,
            selection: Binding(
                get: { selectedTab >= 2 ? selectedTab + 1 : selectedTab },
                set: { index in
                    if index == 2 {
                        // Intercepted tab: opens the player instead of switching.
                        showFullPlayer = true
                    } else {
                        selectedTab = index > 2 ? index - 1 : index
                    }
                }
            ),
            width: geometry.size.width * AmberTheme.dockWidthRatio,
            height: AmberTheme.dockHeight
        )
    }

    private var dockItems: [AmberDockItem] {
        [
            AmberDockItem(icon: "square.stack.fill", title: "资料库"),
            AmberDockItem(icon: "magnifyingglass", title: "发现"),
            AmberDockItem(icon: "play.circle.fill", title: "播放"),
            AmberDockItem(icon: "gearshape.fill", title: "设置"),
        ]
    }

    private func bottomClearance(for geo: GeometryProxy) -> CGFloat {
        if geo.safeAreaInsets.bottom > 0 {
            return max(10, geo.safeAreaInsets.bottom - 4)
        }
        return AmberTheme.dockBottomGap
    }
}

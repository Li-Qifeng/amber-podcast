import SwiftUI

public struct MainTabView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var selectedTab: Int = 0
    @State private var showFullPlayer: Bool = false
    @State private var isDockCollapsed: Bool = false
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
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 15)
                            .onChanged { gesture in
                                if gesture.translation.height < -22 && !isDockCollapsed {
                                    withAnimation(ForwardMotion.fluidSheet) {
                                        isDockCollapsed = true
                                    }
                                } else if gesture.translation.height > 22 && isDockCollapsed {
                                    withAnimation(ForwardMotion.fluidSheet) {
                                        isDockCollapsed = false
                                    }
                                }
                            }
                    )

                // Bottom Floating Island Stack: Apple Podcasts Style Immersive Dock & MiniPlayer
                AmberGlassContainer(spacing: 8) {
                    VStack(spacing: isDockCollapsed ? 0 : 12) {
                        if player.currentEpisode != nil {
                            MiniPlayerView(showFullPlayer: $showFullPlayer)
                                .frame(width: geo.size.width * (isDockCollapsed ? 0.94 : AmberTheme.dockWidthRatio))
                                .amberGlassID("miniPlayer", in: dockNamespace)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .onTapGesture {
                                    if isDockCollapsed {
                                        withAnimation(ForwardMotion.snapSpring) {
                                            isDockCollapsed = false
                                        }
                                    }
                                    showFullPlayer = true
                                }
                        }

                        floatingLiquidDock(geometry: geo)
                            .offset(y: isDockCollapsed ? (AmberTheme.dockHeight + 80) : 0)
                            .opacity(isDockCollapsed ? 0.0 : 1.0)
                            .animation(ForwardMotion.fluidSheet, value: isDockCollapsed)
                    }
                }
                .padding(.bottom, isDockCollapsed ? max(geo.safeAreaInsets.bottom, 12) : (max(geo.safeAreaInsets.bottom, 8) + 10))
                .animation(ForwardMotion.fluidSheet, value: isDockCollapsed)
                .animation(ForwardMotion.fluidSheet, value: player.currentEpisode?.id)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .onChange(of: selectedTab) { _ in
            withAnimation(ForwardMotion.snapSpring) {
                isDockCollapsed = false
            }
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
    private func floatingLiquidDock(geometry: GeometryProxy) -> some View {
        AmberTabBarRendering.dock(
            items: dockItems,
            selection: $selectedTab,
            width: geometry.size.width * AmberTheme.dockWidthRatio,
            height: AmberTheme.dockHeight
        )
    }

    private var dockItems: [AmberDockItem] {
        [
            AmberDockItem(icon: "house.fill", title: "首页"),
            AmberDockItem(icon: "square.stack.fill", title: "资料库"),
            AmberDockItem(icon: "magnifyingglass", title: "发现"),
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

import SwiftUI

public struct MainTabView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var selectedTab: Int = 0
    @State private var showFullPlayer: Bool = false

    #if DEBUG
    /// Stretches the tab spring so headless frame capture can see mid-transition.
    private var demoTabsSlowMotion: Bool {
        ProcessInfo.processInfo.arguments.contains("-amberSlowMotion")
    }

    private var demoTabAnimation: Animation {
        if demoTabsSlowMotion {
            return .spring(response: 2.0, dampingFraction: 0.82)
        }
        return ForwardMotion.mercuryTab
    }
    #endif

    public init() {}

    public var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                NativeApplePodcastTabView(
                    selectedTab: $selectedTab,
                    showFullPlayer: $showFullPlayer,
                    player: player
                )
            } else {
                FallbackTabView(
                    selectedTab: $selectedTab,
                    showFullPlayer: $showFullPlayer,
                    player: player
                )
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
}

// MARK: - Native Apple Podcasts Liquid Glass Tab View (iOS 26+)
@available(iOS 26.0, *)
private struct NativeApplePodcastTabView: View {
    @Binding var selectedTab: Int
    @Binding var showFullPlayer: Bool
    @ObservedObject var player: DualTrackAudioPlayer

    var body: some View {
        Group {
            if player.currentEpisode != nil {
                TabView(selection: $selectedTab) {
                    Tab("首页", systemImage: "house.fill", value: 0) {
                        HomeLibraryView()
                    }

                    Tab("资料库", systemImage: "square.stack.fill", value: 1) {
                        NativeLibraryCatalogView()
                    }

                    Tab("转储", systemImage: "arrow.triangle.2.circlepath.circle.fill", value: 2) {
                        PipelineStatusView()
                    }

                    Tab("搜索", systemImage: "magnifyingglass", value: 3, role: .search) {
                        SearchView()
                    }
                }
                .tint(AmberTheme.primaryAmber)
                .tabBarMinimizeBehavior(.onScrollDown)
                .tabViewBottomAccessory {
                    NativeMiniPlayerAccessory(showFullPlayer: $showFullPlayer, player: player)
                }
            } else {
                TabView(selection: $selectedTab) {
                    Tab("首页", systemImage: "house.fill", value: 0) {
                        HomeLibraryView()
                    }

                    Tab("资料库", systemImage: "square.stack.fill", value: 1) {
                        NativeLibraryCatalogView()
                    }

                    Tab("转储", systemImage: "arrow.triangle.2.circlepath.circle.fill", value: 2) {
                        PipelineStatusView()
                    }

                    Tab("搜索", systemImage: "magnifyingglass", value: 3, role: .search) {
                        SearchView()
                    }
                }
                .tint(AmberTheme.primaryAmber)
                .tabBarMinimizeBehavior(.onScrollDown)
            }
        }
    }
}

@available(iOS 26.0, *)
private struct NativeMiniPlayerAccessory: View {
    @Binding var showFullPlayer: Bool
    @ObservedObject var player: DualTrackAudioPlayer
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        MiniPlayerView(
            showFullPlayer: $showFullPlayer,
            isCompact: placement == .inline,
            hasGlassBackground: false
        )
        .onTapGesture {
            showFullPlayer = true
        }
    }
}

// MARK: - Fallback Tab View (iOS 17+)
private struct FallbackTabView: View {
    @Binding var selectedTab: Int
    @Binding var showFullPlayer: Bool
    @ObservedObject var player: DualTrackAudioPlayer
    @ObservedObject private var scrollCoordinator = AmberScrollCoordinator.shared

    private var dockItems: [AmberDockItem] {
        [
            AmberDockItem(icon: "house.fill", title: "首页"),
            AmberDockItem(icon: "square.stack.fill", title: "资料库"),
            AmberDockItem(icon: "arrow.triangle.2.circlepath.circle.fill", title: "转储"),
            AmberDockItem(icon: "magnifyingglass", title: "搜索"),
        ]
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background Layer: Dark Obsidian
                AmberTheme.background
                    .ignoresSafeArea()

                // Main Content Switching Layer
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()

                if scrollCoordinator.isDockCollapsed && player.currentEpisode != nil {
                    // Collapsed 3-piece layout: [Home Left] --- [MiniPlayer Middle] --- [Search Right]
                    HStack(spacing: 10) {
                        Button {
                            selectedTab = 0
                        } label: {
                            Image(systemName: "house.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(selectedTab == 0 ? AmberTheme.primaryAmber : AmberTheme.labelSecondary)
                                .frame(width: 44, height: 44)
                                .amberGlass(.circle, isInteractive: true)
                        }

                        MiniPlayerView(
                            showFullPlayer: $showFullPlayer,
                            isCompact: true,
                            hasGlassBackground: true
                        )
                        .frame(maxWidth: .infinity)
                        .onTapGesture {
                            showFullPlayer = true
                        }

                        Button {
                            selectedTab = 3
                        } label: {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(selectedTab == 3 ? AmberTheme.primaryAmber : AmberTheme.labelSecondary)
                                .frame(width: 44, height: 44)
                                .amberGlass(.circle, isInteractive: true)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 8) + 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    // Expanded stack: 8pt vertical gap between floating MiniPlayer & Dock
                    VStack(spacing: 8) {
                        if player.currentEpisode != nil {
                            MiniPlayerView(
                                showFullPlayer: $showFullPlayer,
                                isCompact: false,
                                hasGlassBackground: true
                            )
                            .frame(width: min(geo.size.width - 32, 560), height: 54)
                            .onTapGesture {
                                showFullPlayer = true
                            }
                        }

                        AmberTabBarRendering.dock(
                            items: dockItems,
                            selection: $selectedTab,
                            width: min(geo.size.width * AmberTheme.dockWidthRatio, 420),
                            height: AmberTheme.dockHeight
                        )
                    }
                    .padding(.bottom, max(geo.safeAreaInsets.bottom, 8) + 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(ForwardMotion.fluidDockMorph, value: scrollCoordinator.isDockCollapsed)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case 0:
            HomeLibraryView()
        case 1:
            NativeLibraryCatalogView()
        case 2:
            PipelineStatusView()
        case 3:
            SearchView()
        default:
            HomeLibraryView()
        }
    }
}

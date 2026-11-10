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

                    Tab("发现", systemImage: "magnifyingglass", value: 2) {
                        SearchView()
                    }

                    Tab("设置", systemImage: "gearshape.fill", value: 3) {
                        SettingsView()
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

                    Tab("发现", systemImage: "magnifyingglass", value: 2) {
                        SearchView()
                    }

                    Tab("设置", systemImage: "gearshape.fill", value: 3) {
                        SettingsView()
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

    private var dockItems: [AmberDockItem] {
        [
            AmberDockItem(icon: "house.fill", title: "首页"),
            AmberDockItem(icon: "square.stack.fill", title: "资料库"),
            AmberDockItem(icon: "magnifyingglass", title: "发现"),
            AmberDockItem(icon: "gearshape.fill", title: "设置"),
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

                // Clean 8pt vertical stack: zero overlap guaranteed
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
            }
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
            SearchView()
        case 3:
            SettingsView()
        default:
            HomeLibraryView()
        }
    }
}

import SwiftUI

public struct MainTabView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var selectedTab: Int = 0
    @State private var showFullPlayer: Bool = false
    @Namespace private var dockNamespace

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

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
                            .amberGlassID("dock", in: dockNamespace)
                    }
                }
                .padding(.bottom, max(geo.safeAreaInsets.bottom, 8))
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

    // MARK: - Native Liquid Glass Dock (glass field supplied by the parent container)
    private func floatingLiquidDock(geometry: GeometryProxy) -> some View {
        let dockWidth = geometry.size.width * AmberTheme.dockWidthRatio

        return HStack(spacing: 0) {
            dockItem(index: 0, icon: "square.stack.fill", title: "资料库")
            dockItem(index: 1, icon: "magnifyingglass", title: "发现")
            dockItem(index: 2, icon: "gearshape.fill", title: "设置")
        }
        .padding(4)
        .frame(width: dockWidth, height: AmberTheme.dockHeight)
        .amberGlass(.capsule, isInteractive: true)
    }

    private func dockItem(index: Int, icon: String, title: String) -> some View {
        let isSelected = selectedTab == index

        return Button {
            impactFeedback.impactOccurred()
            withAnimation(demoTabAnimation) {
                selectedTab = index
            }
        } label: {
            ZStack {
                if isSelected {
                    // Selection blob is real glass so it blends with the dock's field
                    Capsule()
                        .amberGlass(.capsule, tint: AmberTheme.primaryAmber.opacity(0.07))
                        .amberGlassID("activeDockIndicator", in: dockNamespace)
                }

                VStack(spacing: 3) {
                    Image(systemName: icon)
                        .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? AmberTheme.labelPrimary : AmberTheme.labelTertiary)
                        .scaleEffect(isSelected ? 1.04 : 1.0)

                    Text(title)
                        .font(.system(size: 10, weight: isSelected ? .medium : .regular, design: .rounded))
                        .foregroundStyle(isSelected ? AmberTheme.primaryAmber : AmberTheme.labelTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func bottomClearance(for geo: GeometryProxy) -> CGFloat {
        if geo.safeAreaInsets.bottom > 0 {
            return max(10, geo.safeAreaInsets.bottom - 4)
        }
        return AmberTheme.dockBottomGap
    }
}

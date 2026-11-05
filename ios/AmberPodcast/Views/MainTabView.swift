import SwiftUI

public struct MainTabView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var selectedTab: Int = 0
    @State private var showFullPlayer: Bool = false
    @Namespace private var dockNamespace

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

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

                // Bottom Floating Island Stack: MiniPlayer + Liquid Glass Dock
                VStack(spacing: 8) {
                    if player.currentEpisode != nil {
                        MiniPlayerView(showFullPlayer: $showFullPlayer)
                            .frame(width: geo.size.width * AmberTheme.dockWidthRatio)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    floatingLiquidDock(geometry: geo)
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

    // MARK: - Native Liquid Glass Dock (GlassEffectContainer)
    private func floatingLiquidDock(geometry: GeometryProxy) -> some View {
        let dockWidth = geometry.size.width * AmberTheme.dockWidthRatio

        return AmberGlassContainer(spacing: 8) {
            HStack(spacing: 0) {
                dockItem(index: 0, icon: "square.stack.fill", title: "资料库")
                dockItem(index: 1, icon: "magnifyingglass", title: "发现")
                dockItem(index: 2, icon: "gearshape.fill", title: "设置")
            }
            .padding(4)
            .frame(width: dockWidth, height: AmberTheme.dockHeight)
            .amberGlass(.capsule, isInteractive: true)
        }
    }

    private func dockItem(index: Int, icon: String, title: String) -> some View {
        let isSelected = selectedTab == index

        return Button {
            impactFeedback.impactOccurred()
            withAnimation(ForwardMotion.mercuryTab) {
                selectedTab = index
            }
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(AmberTheme.surfaceRaised)
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                        .matchedGeometryEffect(id: "activeDockIndicator", in: dockNamespace)
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
        .buttonStyle(TactileButtonStyle(scale: 0.94))
    }

    private func bottomClearance(for geo: GeometryProxy) -> CGFloat {
        if geo.safeAreaInsets.bottom > 0 {
            return max(10, geo.safeAreaInsets.bottom - 4)
        }
        return AmberTheme.dockBottomGap
    }
}

import SwiftUI

public struct MainTabView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var selectedTab: Int = 0
    @State private var showFullPlayer: Bool = false

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Main Content Switching by selectedTab
                Group {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

                // Bottom Floating Stack: MiniPlayer + Liquid Glass Dock
                VStack(spacing: 8) {
                    // Floating MiniPlayer (Liquid Glass Capsule Island)
                    if player.currentEpisode != nil {
                        MiniPlayerView(showFullPlayer: $showFullPlayer)
                            .frame(width: geo.size.width * AmberTheme.dockWidthRatio)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Floating Liquid Glass Navigation Dock
                    floatingNavigationDock(geometry: geo)
                }
                .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? max(10, geo.safeAreaInsets.bottom - 4) : AmberTheme.dockBottomGap)
                .animation(ForwardMotion.fluidSheet, value: player.currentEpisode?.id)
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        // Immersive Apple Fluid Full Screen Player
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView(isPresented: $showFullPlayer)
        }
    }

    // MARK: - Floating Liquid Glass Dock
    private func floatingNavigationDock(geometry: GeometryProxy) -> some View {
        let dockWidth = geometry.size.width * AmberTheme.dockWidthRatio

        return HStack(spacing: 0) {
            dockTabButton(index: 0, icon: "square.stack.fill", title: "资料库")
            dockTabButton(index: 1, icon: "magnifyingglass", title: "发现")
            dockTabButton(index: 2, icon: "gearshape.fill", title: "设置")
        }
        .frame(width: dockWidth, height: AmberTheme.dockHeight)
        .liquidGlassCapsule()
    }

    private func dockTabButton(index: Int, icon: String, title: String) -> some View {
        let isSelected = selectedTab == index
        return Button {
            impactFeedback.impactOccurred()
            withAnimation(ForwardMotion.snapSpring) {
                selectedTab = index
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? AmberTheme.primaryAmber : AmberTheme.labelTertiary)

                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? AmberTheme.primaryAmber : AmberTheme.labelTertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tactilePress(scale: 0.92)
    }
}

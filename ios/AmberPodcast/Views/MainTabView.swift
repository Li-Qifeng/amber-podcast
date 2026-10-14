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
        .padding(4)
        .frame(width: dockWidth, height: AmberTheme.dockHeight)
        .liquidGlassCapsule()
    }

    private func dockTabButton(index: Int, icon: String, title: String) -> some View {
        let isSelected = selectedTab == index
        return Button {
            impactFeedback.impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selectedTab = index
            }
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    AmberTheme.primaryAmber.opacity(0.26),
                                    AmberTheme.primaryAmber.opacity(0.10)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.65),
                                            AmberTheme.primaryAmber.opacity(0.50),
                                            Color.white.opacity(0.15)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.8
                                )
                        )
                        .shadow(color: AmberTheme.primaryAmber.opacity(0.35), radius: 6, y: 2)
                        .matchedGeometryEffect(id: "activeDockIndicator", in: dockNamespace)
                }

                VStack(spacing: 3) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? Color.white : AmberTheme.labelTertiary)
                        .scaleEffect(isSelected ? 1.08 : 1.0)

                    Text(title)
                        .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(isSelected ? AmberTheme.primaryAmber : AmberTheme.labelTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle(scale: 0.93))
    }
}

import SwiftUI

public struct MainTabView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var selectedTab: Int = 0
    @State private var showFullPlayer: Bool = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .bottom) {
            // Main Tab View
            TabView(selection: $selectedTab) {
                HomeLibraryView()
                    .tabItem {
                        Label("资料库", systemImage: "square.stack.fill")
                    }
                    .tag(0)

                SearchView()
                    .tabItem {
                        Label("发现", systemImage: "magnifyingglass")
                    }
                    .tag(1)

                SettingsView()
                    .tabItem {
                        Label("设置", systemImage: "gearshape.fill")
                    }
                    .tag(2)
            }
            .tint(AmberTheme.primaryAmber)

            // Forward/Rex Style Floating MiniPlayer docked above TabBar
            if player.currentEpisode != nil {
                MiniPlayerView(showFullPlayer: $showFullPlayer)
                    .padding(.bottom, 54) // Precise clearance above native TabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(AmberTheme.fluidSpring, value: player.currentEpisode?.id)
            }
        }
        .preferredColorScheme(.dark)
        // Fluid Full-Screen Cover for Apple-style immersive Player
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView(isPresented: $showFullPlayer)
        }
    }
}

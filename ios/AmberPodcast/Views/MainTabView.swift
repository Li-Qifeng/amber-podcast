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

            // Floating MiniPlayer docked above TabBar
            if player.currentEpisode != nil {
                MiniPlayerView(showFullPlayer: $showFullPlayer)
                    .padding(.bottom, 54) // Clearance above native TabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: player.currentEpisode?.id)
            }
        }
        // Modal sheet for Apple-style Full Screen Player
        .fullScreenCover(isPresented: $showFullPlayer) {
            FullPlayerView(isPresented: $showFullPlayer)
        }
    }
}

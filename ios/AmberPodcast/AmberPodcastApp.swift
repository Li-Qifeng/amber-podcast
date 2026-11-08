import SwiftUI
import AVFoundation

@main
struct AmberPodcastApp: App {
    init() {
        // Configure native audio session for background playback and AirPlay
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("Failed to activate AVAudioSession: \(error)")
        }

        // Configure navigation bar and tab bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance

        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    @AppStorage("amber_appearance_mode") private var appearanceMode: String = "system"

    private var activeColorScheme: ColorScheme? {
        switch appearanceMode {
        case "dark": return .dark
        case "light": return .light
        default: return nil // Follow iOS System Appearance
        }
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .preferredColorScheme(activeColorScheme)
                .onAppear {
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-amberDemoPlaying") {
                        DualTrackAudioPlayer.shared.seedDemoNowPlaying()
                    }
                    #endif
                }
        }
    }
}

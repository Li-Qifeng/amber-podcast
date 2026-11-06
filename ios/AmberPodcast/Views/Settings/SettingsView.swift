import SwiftUI

public struct SettingsView: View {
    @ObservedObject var apiClient = AmberAPIClient.shared
    @ObservedObject var player = DualTrackAudioPlayer.shared

    @State private var serverUrl: String = ""
    @State private var authToken: String = ""
    @State private var showSavedAlert: Bool = false
    /// Persisted default track mode. Previously a plain @State that nothing read,
    /// so changing it had no effect on playback.
    @AppStorage("amber_default_track_mode") private var preferredTrackModeRaw: String = TrackMode.chinese.rawValue

    private var preferredTrackMode: Binding<TrackMode> {
        Binding(
            get: { TrackMode(rawValue: preferredTrackModeRaw) ?? .chinese },
            set: { newValue in
                preferredTrackModeRaw = newValue.rawValue
                player.switchTrackMode(to: newValue)
            }
        )
    }

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AmberTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Section 1: Server Gateway
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("后端网关服务")

                            VStack(spacing: 12) {
                                HStack {
                                    Text("服务器地址")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AmberTheme.labelPrimary)
                                    Spacer()
                                    TextField("https://podcast.refoxai.com", text: $serverUrl)
                                        .font(.system(size: 13))
                                        .multilineTextAlignment(.trailing)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                        .foregroundStyle(AmberTheme.labelSecondary)
                                }

                                Divider().background(Color.white.opacity(0.08))

                                HStack {
                                    Text("认证令牌")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AmberTheme.labelPrimary)
                                    Spacer()
                                    SecureField("Bearer Token", text: $authToken)
                                        .font(.system(size: 13))
                                        .multilineTextAlignment(.trailing)
                                        .autocorrectionDisabled()
                                        .textInputAutocapitalization(.never)
                                        .foregroundStyle(AmberTheme.labelSecondary)
                                }

                                Divider().background(Color.white.opacity(0.08))

                                Button {
                                    apiClient.serverBaseUrl = serverUrl
                                    apiClient.authToken = authToken
                                    impactFeedback.impactOccurred()
                                    showSavedAlert = true
                                } label: {
                                    HStack {
                                        Spacer()
                                        Text("保存服务设置")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(AmberTheme.primaryAmber)
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(TactileButtonStyle(scale: 0.96))
                            }
                            .padding(16)
                            .amberPlate(radius: AmberTheme.radiusCardRow)

                            Text("Amber 控制面托管于您的专属服务器，数据流直连 Google Drive 5TB 高速存储。")
                                .font(.system(size: 11.5))
                                .foregroundStyle(AmberTheme.labelTertiary)
                                .padding(.horizontal, 4)
                        }

                        // Section 2: Playback Preferences
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("播放与音频增强")

                            VStack(spacing: 12) {
                                HStack {
                                    Text("默认音轨模式")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AmberTheme.labelPrimary)
                                    Spacer()
                                    Picker("", selection: preferredTrackMode) {
                                        ForEach(TrackMode.allCases, id: \.self) { mode in
                                            Text(mode.title).tag(mode)
                                        }
                                    }
                                    .tint(AmberTheme.primaryAmber)
                                }

                                Divider().background(Color.white.opacity(0.08))

                                // Vocal Boost was a toggle with no audio path behind it
                                // (no AVAudioEngine / EQ anywhere in the project), and it
                                // was hidden from users with an accessibility/deceit risk. It
                                // ships again only when the EQ chain is real.
                            }
                            .padding(16)
                            .amberPlate(radius: AmberTheme.radiusCardRow)
                        }

                        // Section 3: Storage & Cache
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("存储与缓存管理")

                            VStack(spacing: 12) {
                                HStack {
                                    Text("云端存储池")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AmberTheme.labelPrimary)
                                    Spacer()
                                    Text("Google Drive 5.0 TB")
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(AmberTheme.labelSecondary)
                                }

                                Divider().background(Color.white.opacity(0.08))

                                HStack {
                                    Text("本地临时缓存")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AmberTheme.labelPrimary)
                                    Spacer()
                                    Button("清除缓存") {
                                        impactFeedback.impactOccurred()
                                        URLCache.shared.removeAllCachedResponses()
                                    }
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundStyle(Color.red.opacity(0.85))
                                }
                            }
                            .padding(16)
                            .amberPlate(radius: AmberTheme.radiusCardRow)
                        }

                        // Section 4: Engine Specs
                        VStack(alignment: .leading, spacing: 10) {
                            sectionHeader("关于 Amber")

                            VStack(spacing: 12) {
                                HStack {
                                    Text("版本")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AmberTheme.labelPrimary)
                                    Spacer()
                                    Text("1.0.0 (Forward Fluid Build)")
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                        .foregroundStyle(AmberTheme.labelSecondary)
                                }

                                Divider().background(Color.white.opacity(0.08))

                                HStack {
                                    Text("AI 双轨管线")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(AmberTheme.labelPrimary)
                                    Spacer()
                                    Text("Whisper Turbo + Gemini 3.8 Flash")
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(AmberTheme.primaryAmber)
                                }
                            }
                            .padding(16)
                            .amberPlate(radius: AmberTheme.radiusCardRow)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 120) // Clearance for floating MiniPlayer
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                self.serverUrl = apiClient.serverBaseUrl
                self.authToken = apiClient.authToken
            }
            .alert("设置已保存", isPresented: $showSavedAlert) {
                Button("好", role: .cancel) {}
            }
            .preferredColorScheme(.dark)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AmberTheme.labelTertiary)
            .padding(.leading, 4)
    }
}

import SwiftUI

public struct SettingsView: View {
    @ObservedObject var apiClient = AmberAPIClient.shared
    @ObservedObject var player = DualTrackAudioPlayer.shared

    @State private var serverUrl: String = ""
    @State private var authToken: String = ""
    @State private var showSavedAlert: Bool = false
    @State private var preferredTrackMode: TrackMode = .chinese

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
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundStyle(AmberTheme.primaryAmber)
                                        Spacer()
                                    }
                                    .padding(.vertical, 4)
                                }
                                .amberPressable(scale: 0.96)
                            }
                            .padding(16)
                            .liquidGlassCard(cornerRadius: 16)

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
                                    Picker("", selection: $preferredTrackMode) {
                                        ForEach(TrackMode.allCases, id: \.self) { mode in
                                            Text(mode.title).tag(mode)
                                        }
                                    }
                                    .tint(AmberTheme.primaryAmber)
                                }

                                Divider().background(Color.white.opacity(0.08))

                                Toggle(isOn: $player.isVocalBoostEnabled) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("人声智能增强 (Vocal Boost)")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(AmberTheme.labelPrimary)
                                        Text("微衰减低频轰鸣，突出中频人声清晰度")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(AmberTheme.labelTertiary)
                                    }
                                }
                                .tint(AmberTheme.primaryAmber)
                            }
                            .padding(16)
                            .liquidGlassCard(cornerRadius: 16)
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
                            .liquidGlassCard(cornerRadius: 16)
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
                            .liquidGlassCard(cornerRadius: 16)
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

import SwiftUI

public struct SettingsView: View {
    /// Version shown in About comes from the bundle, not a hardcoded string.
    static var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (build \(build))"
    }

    @ObservedObject var apiClient = AmberAPIClient.shared
    @ObservedObject var player = DualTrackAudioPlayer.shared

    @State private var serverUrl: String = ""
    @State private var authToken: String = ""
    @State private var showSavedAlert: Bool = false
    @State private var isCheckingHealth: Bool = false
    @State private var healthResult: (ok: Bool, message: String)? = nil
    @State private var showClearCacheConfirm: Bool = false
    @State private var showCacheClearedAlert: Bool = false
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
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
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
                                    impactFeedback.impactOccurred()
                                    isCheckingHealth = true
                                    Task {
                                        let result = await apiClient.checkHealth(customUrl: serverUrl)
                                        await MainActor.run {
                                            isCheckingHealth = false
                                            healthResult = result
                                            if result.ok {
                                                apiClient.serverBaseUrl = serverUrl
                                                apiClient.authToken = authToken
                                            }
                                            showSavedAlert = true
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 8) {
                                        Spacer()
                                        if isCheckingHealth {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                        }
                                        Text(isCheckingHealth ? "正在测试网关连通性..." : "测试连接并保存")
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundStyle(AmberTheme.primaryAmber)
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(TactileButtonStyle(scale: 0.96))
                                .disabled(isCheckingHealth)
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
                                        showClearCacheConfirm = true
                                    }
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(AmberTheme.labelSecondary)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4.5)
                                    .background(AmberTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(AmberTheme.borderHairline, lineWidth: 0.5)
                                    )
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
                                    Text(Self.appVersionText)
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
            .alert(
                healthResult?.ok == true ? "服务设置已保存" : "网关连接异常",
                isPresented: $showSavedAlert
            ) {
                Button("好", role: .cancel) {}
            } message: {
                Text(healthResult?.message ?? "设置已保存")
            }
            .confirmationDialog(
                "清除本地缓存",
                isPresented: $showClearCacheConfirm,
                titleVisibility: .visible
            ) {
                Button("清空全部缓存", role: .destructive) {
                    URLCache.shared.removeAllCachedResponses()
                    let tmp = FileManager.default.temporaryDirectory
                    if let items = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
                        for item in items { try? FileManager.default.removeItem(at: item) }
                    }
                    impactFeedback.impactOccurred()
                    showCacheClearedAlert = true
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除本地图片、临时音频切片与网络缓存。")
            }
            .alert("缓存已清除", isPresented: $showCacheClearedAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text("本地临时网络与媒体缓存已全部释放。")
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

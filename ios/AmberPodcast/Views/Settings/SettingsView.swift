import SwiftUI

public struct SettingsView: View {
    /// Version shown in About comes from the bundle, not a hardcoded string.
    static var appVersionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "2.8.1"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (build \(build))"
    }

    @ObservedObject var apiClient = AmberAPIClient.shared
    @ObservedObject var player = DualTrackAudioPlayer.shared

    @State private var serverUrl: String = ""
    @State private var authToken: String = ""
    @State private var showSavedAlert: Bool = false
    @State private var isCheckingHealth: Bool = false
    @State private var healthResult: (ok: Bool, message: String)? = nil
    @State private var pingMs: Int? = nil

    @State private var showClearCacheConfirm: Bool = false
    @State private var showCacheClearedAlert: Bool = false

    // AppStorage Settings
    @AppStorage("amber_default_track_mode") private var preferredTrackModeRaw: String = TrackMode.chinese.rawValue
    @AppStorage("amber_voice_timbre") private var voiceTimbre: String = "natural"
    @AppStorage("amber_auto_translate_wifi") private var autoTranslateWifi: Bool = true
    @AppStorage("amber_skip_silence") private var skipSilence: Bool = false
    @AppStorage("amber_speech_boost") private var speechBoost: Bool = true
    @AppStorage("amber_auto_play_next") private var autoPlayNext: Bool = true
    @AppStorage("amber_forward_interval") private var forwardInterval: Int = 30
    @AppStorage("amber_backward_interval") private var backwardInterval: Int = 15
    @AppStorage("amber_appearance_mode") private var appearanceMode: String = "system"

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
                    VStack(spacing: 22) {
                        // Section 1: Server Gateway & Network
                        gatewaySection

                        // Section 2: AI Translation Preferences
                        aiPreferencesSection

                        // Section 3: Acoustic Playback Engine
                        acousticEngineSection

                        // Section 4: Appearance & Liquid Glass
                        appearanceSection

                        // Section 5: Storage & Cache Governance
                        storageSection

                        // Section 6: About & System Info
                        aboutSection
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
                Button("清空全部本地媒体与索引缓存", role: .destructive) {
                    URLCache.shared.removeAllCachedResponses()
                    AmberImageCache.shared.clearAll()
                    UserDefaults.standard.removeObject(forKey: "amber_cached_library_json_v1")
                    UserDefaults.standard.removeObject(forKey: "amber_cached_discover_json_v1")
                    let tmp = FileManager.default.temporaryDirectory
                    if let items = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
                        for item in items { try? FileManager.default.removeItem(at: item) }
                    }
                    impactFeedback.impactOccurred()
                    showCacheClearedAlert = true
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清空本地压缩封面、临时网络请求与页面离线快照，不影响已订阅播客。")
            }
            .alert("缓存已清除", isPresented: $showCacheClearedAlert) {
                Button("好", role: .cancel) {}
            } message: {
                Text("本地临时网络与媒体缓存已全部释放，重新进入页面时将自动拉取最新数据。")
            }
        }
    }

    // MARK: - Section 1: Server Gateway
    private var gatewaySection: some View {
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
                    let start = Date()
                    Task {
                        let result = await apiClient.checkHealth(customUrl: serverUrl)
                        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                        await MainActor.run {
                            isCheckingHealth = false
                            healthResult = result
                            if result.ok {
                                pingMs = elapsed
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
                        } else if let ms = pingMs {
                            Circle().fill(Color.green).frame(width: 7, height: 7)
                            Text("已连通 · \(ms)ms")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.green)
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

            Text("Amber 控制面托管于大阪高速服务器，热数据走本地高速 NVMe，远端异步镜像冷备。")
                .font(.system(size: 11.5))
                .foregroundStyle(AmberTheme.labelTertiary)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Section 2: AI Translation Preferences
    private var aiPreferencesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("AI 转译与声音首选项")

            VStack(spacing: 12) {
                HStack {
                    Text("默认收听音轨")
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

                HStack {
                    Text("中文配音风格")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AmberTheme.labelPrimary)
                    Spacer()
                    Picker("", selection: $voiceTimbre) {
                        Text("自然日常 (Natural)").tag("natural")
                        Text("专业播音 (Broadcast)").tag("broadcast")
                        Text("主播克隆 (Voice Clone)").tag("clone")
                    }
                    .tint(AmberTheme.primaryAmber)
                }

                Divider().background(Color.white.opacity(0.08))

                Toggle(isOn: $autoTranslateWifi) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Wi-Fi 下自动转译新单集")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AmberTheme.labelPrimary)
                        Text("订阅播客发布新单集时，由服务端自动触发 ASR 与中文 TTS 拼接")
                            .font(.system(size: 11.5))
                            .foregroundStyle(AmberTheme.labelTertiary)
                    }
                }
                .tint(AmberTheme.primaryAmber)
            }
            .padding(16)
            .amberPlate(radius: AmberTheme.radiusCardRow)
        }
    }

    // MARK: - Section 3: Acoustic Playback Engine
    private var acousticEngineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("声学与播放引擎")

            VStack(spacing: 12) {
                HStack {
                    Text("快退步长")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AmberTheme.labelPrimary)
                    Spacer()
                    Picker("", selection: $backwardInterval) {
                        Text("10 秒").tag(10)
                        Text("15 秒").tag(15)
                        Text("30 秒").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }

                Divider().background(Color.white.opacity(0.08))

                HStack {
                    Text("快进步长")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AmberTheme.labelPrimary)
                    Spacer()
                    Picker("", selection: $forwardInterval) {
                        Text("15 秒").tag(15)
                        Text("30 秒").tag(30)
                        Text("45 秒").tag(45)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }

                Divider().background(Color.white.opacity(0.08))

                Toggle("智能跳过静音片段 (Trim Silence)", isOn: $skipSilence)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .tint(AmberTheme.primaryAmber)

                Divider().background(Color.white.opacity(0.08))

                Toggle("人声清晰度增强 (Speech Boost)", isOn: $speechBoost)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .tint(AmberTheme.primaryAmber)

                Divider().background(Color.white.opacity(0.08))

                Toggle("播放完毕后自动连播下一集", isOn: $autoPlayNext)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .tint(AmberTheme.primaryAmber)
            }
            .padding(16)
            .amberPlate(radius: AmberTheme.radiusCardRow)
        }
    }

    // MARK: - Section 4: Appearance & Liquid Glass
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("外观与主题风格")

            VStack(spacing: 12) {
                HStack {
                    Text("界面外观")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AmberTheme.labelPrimary)
                    Spacer()
                    Picker("外观模式", selection: $appearanceMode) {
                        Text("跟随系统").tag("system")
                        Text("深色").tag("dark")
                        Text("浅色").tag("light")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 210)
                }

                Text("支持 Apple 官方播客全套色彩与材质自适应：深色模式深邃静谧，浅色模式羊脂玉通透磨砂，全局控件无缝自平衡。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(AmberTheme.labelTertiary)
                    .lineSpacing(3)
            }
            .padding(16)
            .amberPlate(radius: AmberTheme.radiusCardRow)
        }
    }

    // MARK: - Section 5: Storage & Cache Governance
    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("存储空间与离线管理")

            VStack(spacing: 12) {
                HStack {
                    Text("存储主架构")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AmberTheme.labelPrimary)
                    Spacer()
                    Text("本地高速 NVMe (热) + GDrive (冷)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AmberTheme.labelSecondary)
                }

                Divider().background(Color.white.opacity(0.08))

                HStack {
                    Text("封面图片加速")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AmberTheme.labelPrimary)
                    Spacer()
                    Text("PIL 500x500 Web 优化 · 约 35KB/张")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AmberTheme.primaryAmber)
                }

                Divider().background(Color.white.opacity(0.08))

                HStack {
                    Text("清理离线临时缓存")
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
                }
            }
            .padding(16)
            .amberPlate(radius: AmberTheme.radiusCardRow)
        }
    }

    // MARK: - Section 5: About & AirStore
    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("关于 Amber")

            VStack(spacing: 12) {
                HStack {
                    Text("客户端版本")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AmberTheme.labelPrimary)
                    Spacer()
                    Text(Self.appVersionText)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundStyle(AmberTheme.labelSecondary)
                }

                Divider().background(Color.white.opacity(0.08))

                HStack {
                    Text("架构设计基准")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AmberTheme.labelPrimary)
                    Spacer()
                    Text("Apple Podcasts × 小宇宙 × Bayt")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AmberTheme.primaryAmber)
                }

                Divider().background(Color.white.opacity(0.08))

                Link(destination: URL(string: "https://store.refoxai.com/studio/amber-podcast/")!) {
                    HStack {
                        Text("检查最新版本 (AirStore)")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AmberTheme.primaryAmber)
                        Spacer()
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 13))
                            .foregroundStyle(AmberTheme.primaryAmber)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(16)
            .amberPlate(radius: AmberTheme.radiusCardRow)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(AmberTheme.labelTertiary)
            .padding(.leading, 4)
    }
}

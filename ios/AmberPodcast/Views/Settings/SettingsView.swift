import SwiftUI

public struct SettingsView: View {
    @ObservedObject var apiClient = AmberAPIClient.shared
    @ObservedObject var player = DualTrackAudioPlayer.shared

    @State private var serverUrl: String = ""
    @State private var authToken: String = ""
    @State private var showSavedAlert: Bool = false
    @State private var preferredTrackMode: TrackMode = .chinese

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // Section: Gateway & Sync Service
                Section(header: Text("后端网关服务"), footer: Text("Amber 控制面托管于您的专属轻量服务器，数据流直连 Google Drive 5TB 存储。")) {
                    HStack {
                        Text("服务器地址")
                            .font(.subheadline)
                        Spacer()
                        TextField("https://podcast.refoxai.com", text: $serverUrl)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("认证令牌")
                            .font(.subheadline)
                        Spacer()
                        SecureField("Bearer Token", text: $authToken)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(.secondary)
                    }

                    Button("保存服务设置") {
                        apiClient.serverBaseUrl = serverUrl
                        apiClient.authToken = authToken
                        showSavedAlert = true
                    }
                    .font(.subheadline.bold())
                }

                // Section: Playback Preferences
                Section(header: Text("播放偏好")) {
                    Picker("默认音轨模式", selection: $preferredTrackMode) {
                        ForEach(TrackMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    Toggle("人声智能增强 (Vocal Boost)", isOn: $player.isVocalBoostEnabled)
                }

                // Section: Storage & Cache
                Section(header: Text("存储与缓存")) {
                    HStack {
                        Text("云端存储层")
                        Spacer()
                        Text("Google Drive 5TB")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("本地音频缓存")
                        Spacer()
                        Text("按需 LRU 淘汰")
                            .foregroundStyle(.secondary)
                    }

                    Button("清理本地临时缓存", role: .destructive) {
                        // Clear URLCache
                        URLCache.shared.removeAllCachedResponses()
                    }
                }

                // Section: About
                Section(header: Text("关于")) {
                    HStack {
                        Text("版本")
                        Spacer()
                        Text("1.0.0 (Build 2026.10)")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("核心引擎")
                        Spacer()
                        Text("Whisper Turbo + Gemini + Fluid UI")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("设置")
            .onAppear {
                self.serverUrl = apiClient.serverBaseUrl
                self.authToken = apiClient.authToken
            }
            .alert("设置已保存", isPresented: $showSavedAlert) {
                Button("好", role: .cancel) {}
            }
            .padding(.bottom, 60)
        }
    }
}

import SwiftUI

public struct PipelineStatusView: View {
    @StateObject private var apiClient = AmberAPIClient.shared
    @State private var statusData: AmberAPIClient.PipelineStatusResponse? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showSettingsSheet: Bool = false

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AmberTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // 1. Status Telemetry Cards Grid
                        telemetryCardsSection

                        // 2. 按播客分类的转储状态
                        feedsGroupedSection

                        // 3. Engine & Infrastructure Info
                        infrastructureSection

                        // Bottom clearance for floating Dock & MiniPlayer
                        Color.clear.frame(height: 168)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                .refreshable {
                    await loadStatus()
                }
            }
            .navigationTitle("后台转储")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        impactFeedback.impactOccurred()
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(uiColor: .label))
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                NavigationStack {
                    SettingsView()
                }
            }
            .task {
                await loadStatus()
            }
        }
    }

    // MARK: - 1. Telemetry Cards Section
    private var telemetryCardsSection: some View {
        let summary = statusData?.summary
        let activeCount = summary?.activeCount ?? 0
        let readyCount = summary?.readyCount ?? 0
        let storageMb = summary?.storageMb ?? 0.0

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            // Card 1: Active Tasks
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(activeCount > 0 ? AmberTheme.primaryAmber : AmberTheme.labelTertiary)
                    Spacer()
                    if activeCount > 0 {
                        Circle()
                            .fill(AmberTheme.primaryAmber)
                            .frame(width: 8, height: 8)
                    }
                }
                Text("\(activeCount)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                Text("进行中转写任务")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AmberTheme.labelSecondary)
            }
            .padding(14)
            .amberPlate(radius: 14)

            // Card 2: Ready Archives
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AmberTheme.accentElectric)
                    Spacer()
                    Text("双轨已就绪")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(AmberTheme.accentElectric)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AmberTheme.accentElectric.opacity(0.12), in: Capsule())
                }
                Text("\(readyCount)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                Text("已转储归档单集")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AmberTheme.labelSecondary)
            }
            .padding(14)
            .amberPlate(radius: 14)

            // Card 3: Storage Used
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                    Spacer()
                }
                Text(String(format: "%.1f MB", storageMb))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                Text("转储存储占用")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AmberTheme.labelSecondary)
            }
            .padding(14)
            .amberPlate(radius: 14)

            // Card 4: ASR Engine Status
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AmberTheme.primaryAmber)
                    Spacer()
                    Text("在线")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
                Text("SenseNova")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .lineLimit(1)
                Text("ASR 语音模型")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AmberTheme.labelSecondary)
            }
            .padding(14)
            .amberPlate(radius: 14)
        }
    }

    // MARK: - 2. 按播客分类的转储状态
    private var feedsGroupedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("按播客分类")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                Spacer()
                if let groups = statusData?.feeds, !groups.isEmpty {
                    Text("\(groups.count) 个播客")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AmberTheme.labelSecondary)
                }
            }

            if let groups = statusData?.feeds, !groups.isEmpty {
                ForEach(groups) { group in
                    feedGroupCard(group)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundStyle(AmberTheme.labelTertiary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("暂无转储数据")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AmberTheme.labelPrimary)
                        Text("订阅播客并在单集详情中点击“AI 双语精译”，即可排队处理。")
                            .font(.system(size: 11))
                            .foregroundStyle(AmberTheme.labelTertiary)
                    }
                    Spacer()
                }
                .padding(16)
                .amberPlate(radius: 12)
            }
        }
    }

    private func feedGroupCard(_ group: AmberAPIClient.PipelineFeedGroup) -> some View {
        let activeEps = group.episodes.filter { $0.isProcessing }
        let readyEps = group.episodes.filter { $0.status == "ready" }
        let failedEps = group.episodes.filter { $0.status == "failed" }
        let notable = group.episodes.filter { $0.status != "idle" }.sorted { statusRank($0) < statusRank($1) }

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                feedCover(group.coverUrl)
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.feedTitle)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        statusBadge("\(readyEps.count) 就绪", color: AmberTheme.accentElectric)
                        if !activeEps.isEmpty {
                            statusBadge("\(activeEps.count) 进行中", color: AmberTheme.primaryAmber)
                        }
                        if !failedEps.isEmpty {
                            statusBadge("\(failedEps.count) 失败", color: Color.red)
                        }
                    }
                }
                Spacer()
            }

            if notable.isEmpty {
                Text("暂无转储单集")
                    .font(.system(size: 11))
                    .foregroundStyle(AmberTheme.labelTertiary)
                    .padding(.vertical, 2)
            } else {
                VStack(spacing: 8) {
                    ForEach(notable) { ep in
                        episodeStatusRow(ep, group: group)
                    }
                }
            }
        }
        .padding(14)
        .amberPlate(radius: 12)
    }

    private func feedCover(_ url: String) -> some View {
        Group {
            if let u = URL(string: url), !url.isEmpty {
                CachedAsyncImage(url: u) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    coverPlaceholder
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 40, height: 40)
        .amberMediaCard(radius: 8)
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(white: 0.15))
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "waveform")
                    .font(.system(size: 16))
                    .foregroundStyle(AmberTheme.labelTertiary)
            )
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func episodeStatusRow(_ ep: Episode, group: AmberAPIClient.PipelineFeedGroup) -> some View {
        HStack(spacing: 10) {
            statusIcon(ep)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(ep.title)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .lineLimit(1)
                Text(ep.statusDescription)
                    .font(.system(size: 10.5))
                    .foregroundStyle(statusColor(ep))
                    .lineLimit(1)
            }
            Spacer()
            if ep.isProcessing {
                Text("\(ep.progress)%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.primaryAmber)
            } else if ep.status == "ready" {
                Button {
                    playEpisode(ep, group: group)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AmberTheme.accentElectric)
                }
                .buttonStyle(TactileButtonStyle(scale: 0.92))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if ep.status == "ready" {
                playEpisode(ep, group: group)
            }
        }
    }

    private func statusIcon(_ ep: Episode) -> some View {
        Group {
            if ep.isProcessing {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .foregroundStyle(AmberTheme.primaryAmber)
            } else if ep.status == "failed" {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.red)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AmberTheme.accentElectric)
            }
        }
        .font(.system(size: 14))
    }

    private func statusColor(_ ep: Episode) -> Color {
        if ep.isProcessing { return AmberTheme.primaryAmber }
        if ep.status == "failed" { return Color.red.opacity(0.85) }
        return AmberTheme.labelTertiary
    }

    private func statusRank(_ ep: Episode) -> Int {
        if ep.isProcessing { return 0 }
        if ep.status == "failed" { return 1 }
        return 2
    }

    // MARK: - 3. Infrastructure Section
    private var infrastructureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("流水线架构状态")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AmberTheme.labelPrimary)

            VStack(spacing: 0) {
                infraRow(title: "语音识别 (ASR)", value: statusData?.summary.asrEngine ?? "SenseNova / Whisper", icon: "waveform")
                Divider().background(Color.white.opacity(0.06))
                infraRow(title: "双语精译模型", value: "SenseNova / OpenAI GPT-4o", icon: "character.book.closed.fill")
                Divider().background(Color.white.opacity(0.06))
                infraRow(title: "语音克隆 (TTS)", value: statusData?.summary.ttsEngine ?? "Edge Dual-Track", icon: "speaker.wave.2.fill")
                Divider().background(Color.white.opacity(0.06))
                infraRow(title: "网关健康度", value: statusData?.summary.serverStatus == "healthy" ? "正常运行 (200 OK)" : "连接检查中", icon: "network")
            }
            .amberPlate(radius: 12)
        }
    }

    private func infraRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(AmberTheme.labelSecondary)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(AmberTheme.labelSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AmberTheme.labelPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Actions
    private func loadStatus() async {
        isLoading = true
        do {
            let res = try await apiClient.fetchPipelineStatus()
            await MainActor.run {
                self.statusData = res
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func playEpisode(_ ep: Episode, group: AmberAPIClient.PipelineFeedGroup) {
        impactFeedback.impactOccurred()
        Task {
            // 优先从已订阅 feeds 找完整 feed 对象，找不到则用分组信息构造最小 feed
            let feeds = (try? await apiClient.listFeeds()) ?? []
            let feed = feeds.first(where: { $0.id == ep.feedId })
                ?? PodcastFeed(
                    id: group.feedId,
                    sourceType: "apple_rss",
                    title: group.feedTitle,
                    author: "",
                    feedUrl: "",
                    coverUrl: group.coverUrl,
                    description: ""
                )
            await DualTrackAudioPlayer.shared.playNewEpisode(episode: ep, feed: feed)
        }
    }
}

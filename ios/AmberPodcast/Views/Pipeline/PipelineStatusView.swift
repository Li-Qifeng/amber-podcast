import SwiftUI

public struct PipelineStatusView: View {
    @StateObject private var apiClient = AmberAPIClient.shared
    @State private var statusData: AmberAPIClient.PipelineStatusResponse? = nil
    @State private var queueData: AmberAPIClient.PipelineQueueResponse? = nil
    @State private var statsData: AmberAPIClient.PipelineStatsResponse? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showSettingsSheet: Bool = false

    // Queue console state
    @State private var queueTab: Int = 0              // 0 running / 1 queued / 2 failed / 3 completed
    @State private var searchText: String = ""
    @State private var statusFilter: String? = nil    // nil = all
    @State private var busyEpisodeId: String? = nil
    @State private var toastMessage: String? = nil
    @State private var refreshTask: Task<Void, Never>? = nil

    // Destructive-action confirmation
    @State private var showDeleteConfirm: Bool = false
    @State private var pendingDeleteId: String? = nil
    @State private var pendingDeleteTitle: String = ""

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AmberTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // 1. Today's throughput + 7-day trend
                        statsOverviewSection

                        // 2. Task queue console (running / queued / failed / completed)
                        queueSection

                        // 3. Per-podcast groups + batch actions
                        feedsGroupedSection

                        // 4. Engine & Infrastructure Info
                        infrastructureSection

                        // Bottom clearance for floating Dock & MiniPlayer
                        Color.clear.frame(height: 168)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                .refreshable {
                    await loadAll()
                }
            }
            .navigationTitle("转储")
            .navigationBarTitleDisplayMode(.large)
            .amberImmersiveTopEdge()
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
                await loadAll()
                startAutoRefresh()
            }
            .onDisappear {
                refreshTask?.cancel()
            }
            .confirmationDialog(
                "删除该单集的转储归档？",
                isPresented: $showDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("删除归档", role: .destructive) {
                    if let id = pendingDeleteId {
                        deleteArtifacts(episodeId: id, title: pendingDeleteTitle)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将删除「\(pendingDeleteTitle)」的音频、字幕与笔记，并重置为未转储。此操作不可撤销。")
            }
            .overlay(alignment: .bottom) {
                if let toast = toastMessage {
                    Text(toast)
                        .font(.system(size: 12.5, weight: .medium, design: .rounded))
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .amberGlass(.capsule, isInteractive: false)
                        .padding(.bottom, 190)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    // MARK: - 1. Stats Overview (今日吞吐 + 7 天趋势)
    private var statsOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("转储概览")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                Spacer()
                if let s = statsData {
                    Text("成功率 \(Int((s.successRate * 100).rounded()))%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(s.successRate >= 0.9 ? AmberTheme.accentElectric : Color.orange)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                statTile(icon: "flame.fill", title: "今日转储",
                         value: "\(statsData?.todayDumped ?? 0)", tint: AmberTheme.primaryAmber)
                statTile(icon: "clock.fill", title: "平均耗时",
                         value: avgDurationText, tint: Color.cyan)
                statTile(icon: "checkmark.seal.fill", title: "就绪归档",
                         value: "\(statsData?.totalReady ?? 0)", tint: AmberTheme.accentElectric)
                statTile(icon: "internaldrive.fill", title: "存储占用",
                         value: storageText, tint: Color.green)
            }

            if let trend = statsData?.trend, !trend.isEmpty {
                trendChart(trend)
            }
        }
    }

    private var avgDurationText: String {
        guard let s = statsData, s.avgDurationSec > 0 else { return "—" }
        let m = s.avgDurationSec / 60
        let sec = s.avgDurationSec % 60
        if m >= 60 { return "\(m / 60)h\(m % 60)m" }
        return m > 0 ? "\(m)m\(sec)s" : "\(sec)s"
    }

    private var storageText: String {
        guard let mb = statusData?.summary.storageMb, mb > 0 else { return "—" }
        return mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb)
    }

    private func statTile(icon: String, title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(AmberTheme.labelPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AmberTheme.labelSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .amberPlate(radius: 12)
    }

    private func trendChart(_ trend: [AmberAPIClient.PipelineTrendPoint]) -> some View {
        let peak = max(1, trend.map { $0.count }.max() ?? 1)
        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(trend) { point in
                VStack(spacing: 5) {
                    Text("\(point.count)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AmberTheme.labelTertiary)
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(point.count > 0 ? AmberTheme.primaryAmber.opacity(0.75) : Color.white.opacity(0.08))
                        .frame(height: max(4, CGFloat(point.count) / CGFloat(peak) * 44))
                    Text(String(point.date.suffix(2)))
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .amberPlate(radius: 12)
    }

    // MARK: - 2. Task Queue Console
    private var queueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("任务队列")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                Spacer()
                if let c = queueData?.counts {
                    Text("\(c.running) 进行 · \(c.queued) 排队")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }
            }

            queueTabBar

            let items = currentQueueItems
            if items.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(AmberTheme.labelTertiary)
                    Text(queueEmptyText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(AmberTheme.labelTertiary)
                    Spacer()
                }
                .padding(14)
                .amberPlate(radius: 12)
            } else {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        queueRow(item)
                    }
                }
            }
        }
    }

    private var queueTabBar: some View {
        let counts = queueData?.counts
        let tabs: [(String, Int)] = [
            ("进行中", counts?.running ?? 0),
            ("排队", counts?.queued ?? 0),
            ("失败", counts?.failed ?? 0),
            ("完成", counts?.completed ?? 0),
        ]
        return HStack(spacing: 4) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { idx, tab in
                Button {
                    impactFeedback.impactOccurred()
                    withAnimation(AmberTheme.quickSpring) { queueTab = idx }
                } label: {
                    HStack(spacing: 4) {
                        Text(tab.0)
                            .font(.system(size: 11.5, weight: queueTab == idx ? .semibold : .regular, design: .rounded))
                        if tab.1 > 0 {
                            Text("\(tab.1)")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(queueTab == idx ? AmberTheme.labelPrimary : AmberTheme.labelTertiary)
                        }
                    }
                    .foregroundStyle(queueTab == idx ? AmberTheme.labelPrimary : AmberTheme.labelSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        ZStack {
                            if queueTab == idx {
                                Capsule().fill(Color.white.opacity(0.14))
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(3)
        .amberPlate(radius: 10)
    }

    private var currentQueueItems: [AmberAPIClient.PipelineTaskCard] {
        guard let q = queueData else { return [] }
        let base: [AmberAPIClient.PipelineTaskCard] = {
            switch queueTab {
            case 0: return q.running
            case 1: return q.queued
            case 2: return q.failed
            default: return q.completed
            }
        }()
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        guard !keyword.isEmpty else { return base }
        return base.filter {
            $0.title.localizedCaseInsensitiveContains(keyword) ||
            $0.feedTitle.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var queueEmptyText: String {
        switch queueTab {
        case 0: return "当前没有进行中的转储任务"
        case 1: return "队列已清空"
        case 2: return "没有失败任务，流水线健康"
        default: return "暂无已完成归档"
        }
    }

    private func queueRow(_ item: AmberAPIClient.PipelineTaskCard) -> some View {
        HStack(spacing: 10) {
            queueCover(item.coverUrl)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.feedTitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(AmberTheme.labelTertiary)
                        .lineLimit(1)
                    Text("·")
                        .font(.system(size: 10.5))
                        .foregroundStyle(AmberTheme.labelTertiary)
                    Text(item.elapsedText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }
                if queueTab == 2 && !item.errorMessage.isEmpty {
                    Text(item.errorMessage)
                        .font(.system(size: 10))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            if queueTab == 0 {
                Text("\(item.progress)%")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.primaryAmber)
                actionButton(icon: "stop.circle.fill", tint: Color.orange) { cancelTask(item) }
            } else if queueTab == 2 {
                actionButton(icon: "arrow.clockwise.circle.fill", tint: AmberTheme.primaryAmber) { retryTask(item) }
            } else if queueTab == 3 {
                actionButton(icon: "play.circle.fill", tint: AmberTheme.accentElectric) { playQueueItem(item) }
            }
        }
        .padding(.vertical, 6)
        .opacity(busyEpisodeId == item.episodeId ? 0.5 : 1.0)
    }

    private func queueCover(_ url: String) -> some View {
        Group {
            if let u = URL(string: url), !url.isEmpty {
                CachedAsyncImage(url: u) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Color(white: 0.15)
                }
            } else {
                Color(white: 0.15)
            }
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func actionButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(tint)
        }
        .buttonStyle(TactileButtonStyle(scale: 0.92))
        .disabled(busyEpisodeId != nil)
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
                statusFilterBar

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

    private var statusFilterBar: some View {
        let options: [(String?, String)] = [
            (nil, "全部"),
            ("ready", "就绪"),
            ("transcribing", "转写中"),
            ("failed", "失败"),
            ("idle", "未转储"),
        ]
        return HStack(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let selected = statusFilter == opt.0
                Button {
                    impactFeedback.impactOccurred()
                    withAnimation(AmberTheme.quickSpring) { statusFilter = opt.0 }
                } label: {
                    Text(opt.1)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular, design: .rounded))
                        .foregroundStyle(selected ? AmberTheme.labelPrimary : AmberTheme.labelSecondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(
                            ZStack {
                                if selected {
                                    Capsule().fill(AmberTheme.primaryAmber.opacity(0.18))
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func feedGroupCard(_ group: AmberAPIClient.PipelineFeedGroup) -> some View {
        let activeEps = group.episodes.filter { $0.isProcessing }
        let readyEps = group.episodes.filter { $0.status == "ready" }
        let failedEps = group.episodes.filter { $0.status == "failed" }
        let notable = group.episodes
            .filter { ep in
                guard ep.status != "idle" || statusFilter == "idle" else { return false }
                guard let filter = statusFilter else { return ep.status != "idle" }
                // "转写中" covers every in-flight stage
                if filter == "transcribing" { return ep.isProcessing }
                return ep.status == filter
            }
            .sorted { statusRank($0) < statusRank($1) }

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

                // 一键转储该播客全部未转储单集
                Button {
                    batchQueueFeed(group)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "square.stack.3d.down.right.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("全部转储")
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    }
                    .foregroundStyle(AmberTheme.primaryAmber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(AmberTheme.primaryAmber.opacity(0.12), in: Capsule())
                }
                .buttonStyle(TactileButtonStyle(scale: 0.94))
                .disabled(busyEpisodeId != nil)
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
                Button {
                    cancelTask(episodeId: ep.id, title: ep.title)
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.orange)
                }
                .buttonStyle(TactileButtonStyle(scale: 0.92))
                .disabled(busyEpisodeId != nil)
            } else if ep.status == "failed" {
                Button {
                    retryTask(episodeId: ep.id, title: ep.title)
                } label: {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(AmberTheme.primaryAmber)
                }
                .buttonStyle(TactileButtonStyle(scale: 0.92))
                .disabled(busyEpisodeId != nil)
            } else if ep.status == "ready" {
                Button {
                    pendingDeleteId = ep.id
                    pendingDeleteTitle = ep.title
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }
                .buttonStyle(TactileButtonStyle(scale: 0.92))
                .disabled(busyEpisodeId != nil)
                .padding(.trailing, 6)

                Button {
                    playEpisode(ep, group: group)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(AmberTheme.accentElectric)
                }
                .buttonStyle(TactileButtonStyle(scale: 0.92))
            } else if ep.status == "idle" {
                Button {
                    retryTask(episodeId: ep.id, title: ep.title)
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(AmberTheme.labelSecondary)
                }
                .buttonStyle(TactileButtonStyle(scale: 0.92))
                .disabled(busyEpisodeId != nil)
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
                infraRow(title: "语音识别 (ASR)", value: statusData?.summary.asrEngine ?? "Groq Whisper Large-v3 Turbo", icon: "waveform")
                Divider().background(Color.white.opacity(0.06))
                infraRow(title: "双语精译模型", value: statusData?.summary.llmEngine ?? "Groq Qwen 3.8 27B", icon: "character.book.closed.fill")
                Divider().background(Color.white.opacity(0.06))
                infraRow(title: "语音合成 (TTS)", value: statusData?.summary.ttsEngine ?? "Edge TTS · 4 音色", icon: "speaker.wave.2.fill")
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
    private func loadAll() async {
        isLoading = true
        async let statusTask = try? await apiClient.fetchPipelineStatus()
        async let queueTask = try? await apiClient.fetchPipelineQueue()
        async let statsTask = try? await apiClient.fetchPipelineStats()
        let (s, q, st) = await (statusTask, queueTask, statsTask)
        await MainActor.run {
            if let s = s { self.statusData = s }
            if let q = q { self.queueData = q }
            if let st = st { self.statsData = st }
            self.isLoading = false
        }
    }

    /// Poll while work is in flight; idle otherwise (no wasted requests).
    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                if Task.isCancelled { break }
                let active = (queueData?.counts.running ?? 0) + (queueData?.counts.queued ?? 0)
                guard active > 0 else { continue }
                if let q = try? await apiClient.fetchPipelineQueue() {
                    await MainActor.run { self.queueData = q }
                }
                if let st = try? await apiClient.fetchPipelineStats() {
                    await MainActor.run { self.statsData = st }
                }
            }
        }
    }

    private func cancelTask(_ item: AmberAPIClient.PipelineTaskCard) {
        cancelTask(episodeId: item.episodeId, title: item.title)
    }

    private func cancelTask(episodeId: String, title: String) {
        busyEpisodeId = episodeId
        impactFeedback.impactOccurred()
        Task {
            try? await apiClient.cancelEpisodeTask(episodeId: episodeId)
            await refreshAfterAction("已取消：\(title)")
        }
    }

    private func retryTask(_ item: AmberAPIClient.PipelineTaskCard) {
        retryTask(episodeId: item.episodeId, title: item.title)
    }

    private func retryTask(episodeId: String, title: String) {
        busyEpisodeId = episodeId
        impactFeedback.impactOccurred()
        Task {
            _ = try? await apiClient.batchTranslate(episodeIds: [episodeId], onlyIdle: false)
            await refreshAfterAction("已重新排队：\(title)")
        }
    }

    private func deleteArtifacts(episodeId: String, title: String) {
        busyEpisodeId = episodeId
        impactFeedback.impactOccurred()
        Task {
            try? await apiClient.deleteEpisodeArtifacts(episodeId: episodeId)
            await refreshAfterAction("已删除归档：\(title)")
        }
    }

    private func batchQueueFeed(_ group: AmberAPIClient.PipelineFeedGroup) {
        impactFeedback.impactOccurred()
        Task {
            let res = try? await apiClient.batchTranslate(feedId: group.feedId, onlyIdle: true)
            let queued = res?.queued ?? 0
            let skipped = res?.skipped ?? 0
            await refreshAfterAction("已入队 \(queued) 集（跳过 \(skipped)）")
        }
    }

    private func playQueueItem(_ item: AmberAPIClient.PipelineTaskCard) {
        impactFeedback.impactOccurred()
        Task {
            let feeds = (try? await apiClient.listFeeds()) ?? []
            let feed = feeds.first(where: { $0.id == item.feedId })
                ?? PodcastFeed(
                    id: item.feedId,
                    sourceType: "apple_rss",
                    title: item.feedTitle,
                    author: "",
                    feedUrl: "",
                    coverUrl: item.coverUrl,
                    description: ""
                )
            if let ep = try? await apiClient.getEpisode(episodeId: item.episodeId) {
                await DualTrackAudioPlayer.shared.playNewEpisode(episode: ep, feed: feed)
            }
        }
    }

    @MainActor
    private func refreshAfterAction(_ message: String) async {
        busyEpisodeId = nil
        withAnimation(.easeOut(duration: 0.2)) { toastMessage = message }
        await loadAll()
        try? await Task.sleep(nanoseconds: 2_200_000_000)
        withAnimation(.easeOut(duration: 0.25)) { toastMessage = nil }
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

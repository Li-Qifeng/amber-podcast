import SwiftUI

public struct LyricsSubtitleView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var autoScroll: Bool = true
    @State private var isTriggering: Bool = false
    @State private var pollingStatus: String = "idle"
    @State private var pollingProgress: Int = 0
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert: Bool = false
    @State private var pollingTask: Task<Void, Never>? = nil

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {}

    private var activeStatus: String {
        if pollingStatus != "idle" {
            return pollingStatus
        }
        return player.currentEpisode?.status ?? "idle"
    }

    private var isProcessing: Bool {
        let s = activeStatus
        return s == "pending" || s == "transcribing" || s == "translating" || s == "synthesizing"
    }

    public var body: some View {
        Group {
            if player.fullMapping.isEmpty {
                emptyOrGeneratingView
            } else {
                lyricsScrollView
            }
        }
        .onAppear {
            syncStatusFromCurrentEpisode()
        }
        .onDisappear {
            pollingTask?.cancel()
        }
        .onChange(of: player.currentEpisode?.id) { _ in
            syncStatusFromCurrentEpisode()
        }
        .alert("提示", isPresented: $showErrorAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "操作完成")
        }
    }

    // MARK: - Subtitles Scroll View
    private var lyricsScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 32) {
                    Color.clear.frame(height: 24)

                    ForEach(player.fullMapping) { seg in
                        SubtitleSegmentRow(
                            seg: seg,
                            currentSegmentIndex: player.currentSegmentIndex,
                            trackMode: player.trackMode,
                            onTap: {
                                impactFeedback.impactOccurred()
                                let targetTime = (player.trackMode == .chinese) ? seg.zhRange.start : seg.enRange.start
                                player.seek(to: targetTime)
                            }
                        )
                    }

                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, 28)
            }
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 36)
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 60)
                }
            )
            .onChange(of: player.currentSegmentIndex) { newIndex in
                if autoScroll {
                    withAnimation(AmberTheme.fluidSpring) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Empty / Actionable Generator View
    private var emptyOrGeneratingView: some View {
        VStack(spacing: 18) {
            Spacer()

            if isProcessing {
                // Live Pipeline Progress Card
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(AmberTheme.primaryAmber)

                    VStack(spacing: 6) {
                        Text(statusTitle(activeStatus))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AmberTheme.labelPrimary)

                        Text("云端后台正在流水线处理，您可以继续收听原声。")
                            .font(.system(size: 12))
                            .foregroundStyle(AmberTheme.labelTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Progress Track
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                                .frame(height: 4)

                            Capsule()
                                .fill(AmberTheme.primaryAmber)
                                .frame(width: max(8, geo.size.width * CGFloat(max(10, pollingProgress)) / 100.0), height: 4)
                                .animation(AmberTheme.fluidSpring, value: pollingProgress)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 40)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .amberPlate(radius: 14)
                .padding(.horizontal, 24)

            } else {
        let isChineseEp = isChineseContent(player.currentEpisode?.title ?? "")
        let btnText = isChineseEp ? "一键提取中文字幕与智能章节" : "一键生成双轨配音与逐句字幕"

        return VStack(spacing: 16) {
            Image(systemName: isChineseEp ? "waveform.badge.magnifyingglass" : "sparkles.tv")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AmberTheme.primaryAmber)

            VStack(spacing: 6) {
                Text(isChineseEp ? "尚未提取中文字幕与智能笔记" : "尚未生成 AI 双轨配音与字幕")
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)

                Text(isChineseEp ? "极速 ASR 中文打轴 · 原生母语高保真 · 通义千问提炼章节摘要" : "极速 ASR 逐句打轴 · 通义千问口播台本译制 · 多角色拟真语音合成")
                    .font(.system(size: 12))
                    .foregroundStyle(AmberTheme.labelTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Button {
                startTranslation()
            } label: {
                HStack(spacing: 6) {
                    if isTriggering {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: isChineseEp ? "quote.bubble.fill" : "waveform.badge.plus")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(btnText)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8.5)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(TactileButtonStyle(scale: 0.96))
            .disabled(isTriggering || player.currentEpisode == nil)
        }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .amberPlate(radius: 14)
                .padding(.horizontal, 24)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func isChineseContent(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x4e00 && scalar.value <= 0x9fff {
                return true
            }
        }
        return false
    }

    private func statusTitle(_ s: String) -> String {
        let isChinese = isChineseContent(player.currentEpisode?.title ?? "")
        switch s {
        case "transcribing":
            return isChinese ? "正在极速提取中文字幕打轴 (30%)..." : "正在极速 ASR 识别打轴 (25%)..."
        case "translating":
            return isChinese ? "正在提炼智能章节与核心总结 (65%)..." : "通义千问正在口播译制与提炼章节 (50%)..."
        case "synthesizing":
            return isChinese ? "正在归档并就绪逐句字幕 (90%)..." : "正在多角色拟真语音合成与对齐 (75%)..."
        default:
            return "已提交流水线，正在排队启动..."
        }
    }

    private func syncStatusFromCurrentEpisode() {
        guard let ep = player.currentEpisode else { return }
        self.pollingStatus = ep.status
        self.pollingProgress = ep.progress
        if isProcessing {
            startPolling(episodeId: ep.id)
        }
    }

    private func startTranslation() {
        guard let ep = player.currentEpisode else { return }
        isTriggering = true
        impactFeedback.impactOccurred()

        Task {
            do {
                try await AmberAPIClient.shared.triggerTranslation(episode: ep, feed: player.currentFeed)
                await MainActor.run {
                    self.isTriggering = false
                    self.pollingStatus = "pending"
                    self.pollingProgress = 5
                    self.startPolling(episodeId: ep.id)
                }
            } catch {
                await MainActor.run {
                    self.isTriggering = false
                    self.errorMessage = "提交转译失败: \(error.localizedDescription)"
                    self.showErrorAlert = true
                }
            }
        }
    }

    private func startPolling(episodeId: String) {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                if Task.isCancelled { break }

                if let ep = try? await AmberAPIClient.shared.getEpisode(episodeId: episodeId) {
                    await MainActor.run {
                        self.pollingStatus = ep.status
                        self.pollingProgress = ep.progress
                    }

                    if ep.status == "ready" {
                        // Success! Load artifacts into player
                        if let artifacts = try? await AmberAPIClient.shared.fetchArtifacts(episodeId: episodeId),
                           let currentFeed = player.currentFeed {
                            await MainActor.run {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                player.loadEpisode(episode: ep, feed: currentFeed, artifacts: artifacts, autoPlay: true)
                            }
                        }
                        break
                    } else if ep.status == "failed" {
                        await MainActor.run {
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                            self.errorMessage = "转译流水线失败: \(ep.errorMessage ?? "未知错误")"
                            self.showErrorAlert = true
                        }
                        break
                    }
                }
            }
        }
    }
}

// MARK: - Subtitle Segment Row
private struct SubtitleSegmentRow: View {
    let seg: FullMappingSegment
    let currentSegmentIndex: Int
    let trackMode: TrackMode
    let onTap: () -> Void

    private var isCurrent: Bool {
        seg.index == currentSegmentIndex
    }

    private var distance: Int {
        abs(seg.index - currentSegmentIndex)
    }

    private var secondaryOpacity: Double {
        max(0.18, 0.55 - Double(distance) * 0.12)
    }

    private var blurRadius: CGFloat {
        isCurrent ? 0 : min(1.8, CGFloat(distance) * 0.45)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Speaker & Timestamp Tag
            HStack(spacing: 8) {
                Text(seg.speaker)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isCurrent ? AmberTheme.primaryAmber : AmberTheme.labelTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isCurrent ? AmberTheme.primaryAmber.opacity(0.12) : AmberTheme.surfaceRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(isCurrent ? AmberTheme.primaryAmber.opacity(0.25) : AmberTheme.borderHairline, lineWidth: 0.5)
                    )

                Text(formatSeconds(trackMode == .chinese ? seg.zhRange.start : seg.enRange.start))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(AmberTheme.labelTertiary)

                Spacer()
            }

            // Primary Subtitle Typography
            if trackMode == .chinese {
                Text(seg.zhDisplay)
                    .font(.system(size: isCurrent ? 25 : 19, weight: isCurrent ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isCurrent ? AmberTheme.labelPrimary : AmberTheme.labelSecondary.opacity(secondaryOpacity))
                    .lineSpacing(6)
                    .blur(radius: blurRadius)
                    .scaleEffect(isCurrent ? 1.02 : 1.0, anchor: .leading)
                    .animation(AmberTheme.fluidSpring, value: isCurrent)

                Text(seg.enText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AmberTheme.labelTertiary.opacity(isCurrent ? 0.75 : 0.3))
                    .lineSpacing(3)
            } else {
                Text(seg.enText)
                    .font(.system(size: isCurrent ? 25 : 19, weight: isCurrent ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isCurrent ? AmberTheme.labelPrimary : AmberTheme.labelSecondary.opacity(secondaryOpacity))
                    .lineSpacing(6)
                    .blur(radius: blurRadius)
                    .scaleEffect(isCurrent ? 1.02 : 1.0, anchor: .leading)
                    .animation(AmberTheme.fluidSpring, value: isCurrent)

                Text(seg.zhDisplay)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AmberTheme.labelTertiary.opacity(isCurrent ? 0.75 : 0.3))
                    .lineSpacing(3)
            }
        }
        .id(seg.index)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private func formatSeconds(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds >= 0 else { return "00:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

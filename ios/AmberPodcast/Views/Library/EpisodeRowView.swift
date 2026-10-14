import SwiftUI

public struct EpisodeRowView: View {
    public let episode: Episode
    public let feed: PodcastFeed
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var isTriggering: Bool = false
    @State private var currentStatus: String
    @State private var currentProgress: Int

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init(episode: Episode, feed: PodcastFeed) {
        self.episode = episode
        self.feed = feed
        self._currentStatus = State(initialValue: episode.status)
        self._currentProgress = State(initialValue: episode.progress)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 1. Metadata Line (Date · Duration · Status Badge)
            HStack(spacing: 8) {
                Text(formatDate(episode.pubDate))
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AmberTheme.labelTertiary)

                Text("·")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(AmberTheme.labelTertiary)

                Text(formatDuration(Double(episode.duration)))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(AmberTheme.labelTertiary)

                Spacer()

                // AI Dual-Track Status Indicator Badge
                statusBadge
            }

            // 2. Episode Title with Playing State Indicator
            HStack(alignment: .top, spacing: 8) {
                if isCurrentPlaying && player.isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AmberTheme.primaryAmber)
                        .padding(.top, 2)
                }

                Text(episode.title)
                    .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(isCurrentPlaying ? AmberTheme.primaryAmber : AmberTheme.labelPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            // 3. Shownotes Snippet
            if !episode.shownotes.isEmpty {
                Text(cleanSnippet(episode.shownotes))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AmberTheme.labelSecondary)
                    .lineSpacing(3)
                    .lineLimit(2)
            }

            // 4. Bottom Action Bar (Forward-Style Minimalist Capsules)
            HStack(spacing: 10) {
                // Play / Pause Capsule Button
                Button {
                    playEpisode()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCurrentPlaying && player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text(isCurrentPlaying && player.isPlaying ? "暂停" : (currentStatus == "ready" ? "播放双轨" : "播放原声"))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        isCurrentPlaying ?
                        AmberTheme.primaryAmber :
                        Color.white.opacity(0.1),
                        in: Capsule()
                    )
                    .overlay(
                        Capsule().stroke(isCurrentPlaying ? AmberTheme.primaryAmber : AmberTheme.borderSpecular, lineWidth: 0.5)
                    )
                    .foregroundStyle(isCurrentPlaying ? Color.black : AmberTheme.labelPrimary)
                }
                .buttonStyle(TactileButtonStyle(scale: 0.94))

                // AI Translation Trigger Button (if not ready yet)
                if currentStatus == "idle" || currentStatus == "failed" {
                    Button {
                        triggerTranslation()
                    } label: {
                        HStack(spacing: 5) {
                            if isTriggering {
                                ProgressView()
                                    .scaleEffect(0.65)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            Text(currentStatus == "failed" ? "重试双轨转译" : "生成双轨配音")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(AmberTheme.primaryAmber.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(AmberTheme.primaryAmber.opacity(0.35), lineWidth: 0.5))
                        .foregroundStyle(AmberTheme.primaryAmber)
                    }
                    .buttonStyle(TactileButtonStyle(scale: 0.94))
                    .disabled(isTriggering)
                }

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .lightweightCard(cornerRadius: 16, tint: isCurrentPlaying ? AmberTheme.primaryAmber : nil)
        .contentShape(Rectangle())
        .onTapGesture {
            playEpisode()
        }
    }

    private var isCurrentPlaying: Bool {
        player.currentEpisode?.id == episode.id
    }

    // MARK: - Status Badge (Refined Apple HIG)
    @ViewBuilder
    private var statusBadge: some View {
        switch currentStatus {
        case "ready":
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                Text("双轨已就绪")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AmberTheme.accentElectric)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(AmberTheme.accentElectric.opacity(0.12), in: Capsule())

        case "transcribing", "translating", "synthesizing", "pending":
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.55)
                Text("AI 制作中 \(currentProgress)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(AmberTheme.primaryAmber)
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(AmberTheme.primaryAmber.opacity(0.12), in: Capsule())

        case "failed":
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 10))
                Text("转译失败")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .foregroundStyle(Color.red.opacity(0.85))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Color.red.opacity(0.1), in: Capsule())

        default:
            EmptyView()
        }
    }

    // MARK: - Actions
    private func playEpisode() {
        impactFeedback.impactOccurred()
        Task {
            var artifacts: EpisodeArtifacts? = nil
            if currentStatus == "ready" {
                artifacts = try? await AmberAPIClient.shared.fetchArtifacts(episodeId: episode.id)
            }
            await MainActor.run {
                if isCurrentPlaying {
                    player.togglePlayPause()
                } else {
                    player.loadEpisode(episode: episode, feed: feed, artifacts: artifacts, autoPlay: true)
                }
            }
        }
    }

    private func triggerTranslation() {
        isTriggering = true
        impactFeedback.impactOccurred()
        Task {
            do {
                try await AmberAPIClient.shared.triggerTranslation(episodeId: episode.id)
                await MainActor.run {
                    currentStatus = "pending"
                    currentProgress = 0
                    isTriggering = false
                }
            } catch {
                await MainActor.run {
                    isTriggering = false
                }
            }
        }
    }

    // MARK: - Formatting Helpers
    private func cleanSnippet(_ text: String) -> String {
        return text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func formatDate(_ dateStr: String) -> String {
        guard !dateStr.isEmpty else { return "" }
        if dateStr.count >= 10 {
            return String(dateStr.prefix(10))
        }
        return dateStr
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分"
        } else {
            return "\(minutes)分钟"
        }
    }
}

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
        VStack(alignment: .leading, spacing: 8) {
            // Pub date & duration
            HStack(spacing: 8) {
                Text(formatDate(episode.pubDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("•")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                Text(formatDuration(Double(episode.duration)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                // AI Dual-Track Status Indicator Badge
                statusBadge
            }

            // Episode Title
            Text(episode.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isCurrentPlaying ? Color.accentColor : Color.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            // Shownotes Snippet
            if !episode.shownotes.isEmpty {
                Text(cleanSnippet(episode.shownotes))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            // Bottom Actions (Play / Trigger AI Translation)
            HStack(spacing: 12) {
                // Play Button
                Button {
                    playEpisode()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isCurrentPlaying && player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.caption.bold())
                        Text(isCurrentPlaying && player.isPlaying ? "暂停" : (currentStatus == "ready" ? "播放双轨" : "播放原声"))
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(isCurrentPlaying ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                    .foregroundStyle(isCurrentPlaying ? Color.white : Color.primary)
                }

                // AI Translation Trigger Button (if not ready yet)
                if currentStatus == "idle" || currentStatus == "failed" {
                    Button {
                        triggerTranslation()
                    } label: {
                        HStack(spacing: 4) {
                            if isTriggering {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.caption)
                            }
                            Text(currentStatus == "failed" ? "重试 AI 转译" : "生成双轨配音")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.purple.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.purple)
                    }
                    .disabled(isTriggering)
                }

                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            playEpisode()
        }
    }

    private var isCurrentPlaying: Bool {
        player.currentEpisode?.id == episode.id
    }

    // MARK: - Status Badge
    @ViewBuilder
    private var statusBadge: some View {
        switch currentStatus {
        case "ready":
            HStack(spacing: 4) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                Text("双轨已就绪")
                    .font(.caption2.bold())
            }
            .foregroundStyle(Color.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.green.opacity(0.12), in: Capsule())

        case "transcribing", "translating", "synthesizing", "pending":
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text("AI 制作中 \(currentProgress)%")
                    .font(.caption2.bold().monospacedDigit())
            }
            .foregroundStyle(Color.purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.purple.opacity(0.12), in: Capsule())

        case "failed":
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption2)
                Text("转译失败")
                    .font(.caption2.bold())
            }
            .foregroundStyle(Color.red)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.red.opacity(0.12), in: Capsule())

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

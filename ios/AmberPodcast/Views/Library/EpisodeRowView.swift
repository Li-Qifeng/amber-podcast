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
                let dateStr = formatDate(episode.pubDate)
                let durStr = formatDuration(Double(episode.duration))

                if !dateStr.isEmpty {
                    Text(dateStr)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }

                if !dateStr.isEmpty && !durStr.isEmpty {
                    Text("·")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }

                if !durStr.isEmpty {
                    Text(durStr)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(AmberTheme.labelTertiary)
                }

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
                // Play / Pause Button
                Button {
                    playEpisode()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: isCurrentPlaying && player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 9.5, weight: .bold))
                        Text(isCurrentPlaying && player.isPlaying ? "暂停" : (currentStatus == "ready" ? "播放双轨" : "播放原声"))
                            .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5.5)
                    .background(
                        isCurrentPlaying ?
                        AmberTheme.primaryAmber :
                        AmberTheme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(isCurrentPlaying ? AmberTheme.primaryAmber : AmberTheme.borderHairline, lineWidth: 0.5)
                    )
                    .foregroundStyle(isCurrentPlaying ? Color.black : AmberTheme.labelPrimary)
                }
                .buttonStyle(TactileButtonStyle(scale: 0.96))

                // AI Translation Trigger Button (if not ready yet)
                if currentStatus == "idle" || currentStatus == "failed" {
                    Button {
                        triggerTranslation()
                    } label: {
                        HStack(spacing: 5) {
                            if isTriggering {
                                ProgressView()
                                    .scaleEffect(0.60)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            Text(currentStatus == "failed" ? "重试转译" : "生成双轨")
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5.5)
                        .background(AmberTheme.surfaceRaised, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(AmberTheme.borderHairline, lineWidth: 0.5)
                        )
                        .foregroundStyle(AmberTheme.labelSecondary)
                    }
                    .buttonStyle(TactileButtonStyle(scale: 0.96))
                    .disabled(isTriggering)
                }

                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .amberPlate(radius: AmberTheme.radiusCardRow, isActive: isCurrentPlaying)
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
                    .font(.system(size: 9.5))
                Text("双轨就绪")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundStyle(AmberTheme.accentElectric)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(AmberTheme.accentElectric.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

        case "transcribing", "translating", "synthesizing", "pending":
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.50)
                Text("转译中 \(currentProgress)%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(AmberTheme.primaryAmber)
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(AmberTheme.primaryAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

        case "failed":
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 9.5))
                Text("转译失败")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
            }
            .foregroundStyle(Color.red.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

        default:
            EmptyView()
        }
    }

    // MARK: - Actions
    private func playEpisode() {
        impactFeedback.impactOccurred()
        if isCurrentPlaying {
            if player.isPlaying {
                player.pause()
            } else if player.fullMapping.isEmpty {
                Task { await player.playNewEpisode(episode: episode, feed: feed) }
            } else {
                player.play()
            }
        } else {
            Task { await player.playNewEpisode(episode: episode, feed: feed) }
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

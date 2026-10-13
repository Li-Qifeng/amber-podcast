import SwiftUI

public struct MiniPlayerView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @Binding var showFullPlayer: Bool

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init(showFullPlayer: Binding<Bool>) {
        self._showFullPlayer = showFullPlayer
    }

    public var body: some View {
        if let episode = player.currentEpisode {
            VStack(spacing: 0) {
                // Main mini player floating capsule
                HStack(spacing: 12) {
                    // 1. Cover artwork
                    if let coverUrl = player.currentFeed?.coverUrl, let url = URL(string: coverUrl) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .shadow(radius: 2)
                        } placeholder: {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 44, height: 44)
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "mic.fill").font(.caption).foregroundStyle(.white))
                    }

                    // 2. Titles & Active Track Badge
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            // Current track mode pill badge
                            Text(player.trackMode.title)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(player.trackMode == .chinese ? Color.purple : Color.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(player.trackMode == .chinese ? Color.purple.opacity(0.15) : Color.secondary.opacity(0.12), in: Capsule())

                            Text(player.currentFeed?.title ?? "")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // 3. Play / Pause Button
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                    }

                    // 4. Skip forward 30s
                    Button {
                        player.skipForward(30)
                        impactFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                // Bottom hairline progress indicator
                GeometryReader { barGeo in
                    let effectiveDuration = max(1.0, player.duration)
                    let progress = min(1.0, max(0.0, player.currentTime / effectiveDuration))
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                            .frame(height: 2)

                        Rectangle()
                            .fill(player.trackMode == .chinese ? Color.purple : Color.accentColor)
                            .frame(width: barGeo.size.width * CGFloat(progress), height: 2)
                    }
                }
                .frame(height: 2)
            }
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                impactFeedback.impactOccurred()
                showFullPlayer = true
            }
        }
    }
}

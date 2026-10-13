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
                // Main Mini Player Island Capsule
                HStack(spacing: 12) {
                    // 1. Cover Squircle Artwork
                    ZStack {
                        if let coverUrl = player.currentFeed?.coverUrl, let url = URL(string: coverUrl) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 44, height: 44)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                                    )
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .fill(Color(white: 0.15))
                                    .frame(width: 44, height: 44)
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Color(white: 0.15))
                                .frame(width: 44, height: 44)
                                .overlay(Image(systemName: "headphones").font(.caption).foregroundStyle(.white.opacity(0.6)))
                        }
                    }
                    .shadow(color: Color.black.opacity(0.35), radius: 5, y: 2)

                    // 2. Title & Current Track Mode Pill
                    VStack(alignment: .leading, spacing: 3) {
                        Text(episode.title)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(AmberTheme.labelPrimary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            // Track mode micro badge
                            HStack(spacing: 3) {
                                if player.trackMode == .chinese {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                Text(player.trackMode.title)
                                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(player.trackMode == .chinese ? AmberTheme.primaryAmber : AmberTheme.labelTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(player.trackMode == .chinese ? AmberTheme.primaryAmber.opacity(0.15) : Color.white.opacity(0.06))
                            )

                            Text(player.currentFeed?.title ?? "")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(AmberTheme.labelTertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    // 3. Play / Pause Button with Spring scale
                    Button {
                        player.togglePlayPause()
                        impactFeedback.impactOccurred()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 36, height: 36)
                                .shadow(color: Color.white.opacity(0.15), radius: 6, y: 2)

                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.black)
                                .offset(x: player.isPlaying ? 0 : 1)
                        }
                    }
                    .amberPressable(scale: 0.90)

                    // 4. Skip forward 30s
                    Button {
                        player.skipForward(30)
                        impactFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AmberTheme.labelSecondary)
                            .frame(width: 36, height: 36)
                    }
                    .amberPressable()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                // 5. Hairline Micro Progress Bar on capsule bottom
                GeometryReader { barGeo in
                    let effectiveDuration = max(1.0, player.duration)
                    let progress = min(1.0, max(0.0, player.currentTime / effectiveDuration))
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 2)

                        Rectangle()
                            .fill(player.trackMode == .chinese ? AmberTheme.primaryAmber : Color.white.opacity(0.9))
                            .frame(width: barGeo.size.width * CGFloat(progress), height: 2)
                    }
                }
                .frame(height: 2)
            }
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(AmberTheme.cardSurfaceElevated.opacity(0.85))
                    .background(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AmberTheme.borderSpecular, lineWidth: 0.5)
            )
            .shadow(color: Color.black.opacity(0.4), radius: 16, y: 8)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                impactFeedback.impactOccurred()
                showFullPlayer = true
            }
        }
    }
}

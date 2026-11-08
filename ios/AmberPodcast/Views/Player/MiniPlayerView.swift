import SwiftUI

public struct MiniPlayerView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @Binding var showFullPlayer: Bool

    @State private var dragOffsetY: CGFloat = 0
    @State private var isDragging: Bool = false

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    public init(showFullPlayer: Binding<Bool>) {
        self._showFullPlayer = showFullPlayer
    }

    public var body: some View {
        if let episode = player.currentEpisode {
            VStack(spacing: 0) {
                // Main Mini Player Liquid Glass Capsule Island
                HStack(spacing: 12) {
                    // 1. Cover Artwork (Squircle)
                    coverArtworkView

                    // 2. Titles & Current Track Mode Pill
                    VStack(alignment: .leading, spacing: 2.5) {
                        Text(episode.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AmberTheme.labelPrimary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            trackModeBadge

                            Text(player.currentFeed?.title ?? "")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AmberTheme.labelTertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    // 3. Play / Pause Button with Clean Touch Target
                    Button {
                        player.togglePlayPause()
                        impactFeedback.impactOccurred()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 32, height: 32)
                                .shadow(color: Color.black.opacity(0.25), radius: 4, y: 2)

                            if player.isBuffering {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.black)
                                    .offset(x: player.isPlaying ? 0 : 1)
                            }
                        }
                    }
                    .buttonStyle(TactileButtonStyle(scale: 0.94))

                    // 4. Skip forward 30s
                    Button {
                        player.skipForward(30)
                        impactFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AmberTheme.labelSecondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(TactileButtonStyle(scale: 0.94))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                // 5. Hairline Micro Progress Bar
                progressBarView
            }
            .amberGlass(.capsule, isInteractive: true)
            .offset(y: dragOffsetY)
            .scaleEffect(isDragging ? 1.02 : 1.0)
            .animation(isDragging ? .interactiveSpring() : ForwardMotion.snapSpring, value: dragOffsetY)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        isDragging = true
                        let dy = value.translation.height
                        if dy < 0 {
                            dragOffsetY = dy * 0.82
                        } else {
                            dragOffsetY = dy * 0.18
                        }
                    }
                    .onEnded { value in
                        let dy = value.translation.height
                        let predictedY = value.predictedEndTranslation.height
                        if dy < -50 || predictedY < -110 {
                            impactFeedback.impactOccurred()
                            withAnimation(ForwardMotion.fluidSheet) {
                                showFullPlayer = true
                                dragOffsetY = 0
                                isDragging = false
                            }
                        } else {
                            withAnimation(ForwardMotion.snapSpring) {
                                dragOffsetY = 0
                                isDragging = false
                            }
                        }
                    }
            )
            .onTapGesture {
                impactFeedback.impactOccurred()
                withAnimation(ForwardMotion.fluidSheet) {
                    showFullPlayer = true
                }
            }
        }
    }

    // MARK: - Subviews
    private var coverArtworkView: some View {
        ZStack {
            if let coverUrl = player.currentFeed?.proxiedCoverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .amberMediaCard(radius: 10)
                } placeholder: {
                    coverPlaceholder
                }
            } else {
                coverPlaceholder
            }
        }
    }

    private var coverPlaceholder: some View {
        ZStack {
            Color(white: 0.15)
            Image(systemName: "headphones").font(.caption).foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 40, height: 40)
        .amberMediaCard(radius: 10)
    }

    private var trackModeBadge: some View {
        Text(player.trackMode.title)
            .font(.system(size: 9.5, weight: .medium, design: .rounded))
            .foregroundStyle(player.trackMode == .chinese ? AmberTheme.primaryAmber : AmberTheme.labelTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(player.trackMode == .chinese ? AmberTheme.primaryAmber.opacity(0.12) : AmberTheme.surfaceRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(player.trackMode == .chinese ? AmberTheme.primaryAmber.opacity(0.25) : AmberTheme.borderHairline, lineWidth: 0.5)
            )
    }

    private var progressBarView: some View {
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
        .clipShape(Capsule())
    }
}

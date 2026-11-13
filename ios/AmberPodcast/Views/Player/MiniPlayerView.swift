import SwiftUI

public struct MiniPlayerView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @Binding var showFullPlayer: Bool
    public var isCompact: Bool? = nil
    public var hasGlassBackground: Bool = true

    @State private var dragOffsetY: CGFloat = 0
    @State private var isDragging: Bool = false

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    public init(showFullPlayer: Binding<Bool>, isCompact: Bool? = nil, hasGlassBackground: Bool = true) {
        self._showFullPlayer = showFullPlayer
        self.isCompact = isCompact
        self.hasGlassBackground = hasGlassBackground
    }

    public var body: some View {
        if let episode = player.currentEpisode {
            // Main Mini Player Liquid Glass Capsule
            HStack(spacing: 10) {
                // 1. Cover Artwork: Fixed 38x38 squircle (no resize jitter)
                coverArtworkView

                // 2. Titles: Stable 2-line vertical stack (no height jumping)
                VStack(alignment: .leading, spacing: 2) {
                    Text(episode.title)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        trackModeBadge

                        Text(player.currentFeed?.title ?? "Amber 播客")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AmberTheme.labelTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)

                // 3. Play / Pause Button: Anchored firmly at trailing edge (32x32)
                Button {
                    player.togglePlayPause()
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
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                }
                .buttonStyle(ApplePlayButtonStyle(scale: 0.90))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) {
                // 4. Progress Bar: bottom overlay so it NEVER alters layout vertical center
                progressBarView
                    .padding(.horizontal, 12)
                    .padding(.bottom, 2)
            }
            .modifier(ConditionalGlassModifier(applyGlass: hasGlassBackground))
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
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 38, height: 38)
                        .amberMediaCard(radius: 8)
                } placeholder: {
                    coverPlaceholder
                }
            } else {
                coverPlaceholder
            }
        }
        .frame(width: 38, height: 38)
    }

    private var coverPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(white: 0.15))
            .frame(width: 38, height: 38)
            .overlay(
                Image(systemName: "headphones")
                    .font(.system(size: 15))
                    .foregroundStyle(AmberTheme.primaryAmber)
            )
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

private struct ConditionalGlassModifier: ViewModifier {
    let applyGlass: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if applyGlass {
            content.amberGlass(.capsule, isInteractive: true)
        } else {
            content
        }
    }
}

import SwiftUI

public struct MiniPlayerView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @Binding var showFullPlayer: Bool

    @State private var dragOffsetY: CGFloat = 0
    @State private var isDragging: Bool = false
    @State private var isPressed: Bool = false

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    public init(showFullPlayer: Binding<Bool>) {
        self._showFullPlayer = showFullPlayer
    }

    public var body: some View {
        if let episode = player.currentEpisode {
            VStack(spacing: 0) {
                // Main Mini Player Liquid Glass Capsule Island
                HStack(spacing: 12) {
                    // 1. Cover Squircle Artwork (38x38 pt)
                    ZStack {
                        if let coverUrl = player.currentFeed?.coverUrl, let url = URL(string: coverUrl) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 40, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.18), lineWidth: 0.5)
                                    )
                            } placeholder: {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color(white: 0.15))
                                    .frame(width: 40, height: 40)
                            }
                        } else {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(white: 0.15))
                                .frame(width: 40, height: 40)
                                .overlay(Image(systemName: "headphones").font(.caption).foregroundStyle(.white.opacity(0.6)))
                        }
                    }
                    .shadow(color: Color.black.opacity(0.4), radius: 6, y: 3)

                    // 2. Titles & Current Track Mode Pill
                    VStack(alignment: .leading, spacing: 2.5) {
                        Text(episode.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(AmberTheme.labelPrimary)
                            .lineLimit(1)

                        HStack(spacing: 6) {
                            // Track mode micro badge
                            HStack(spacing: 3) {
                                if player.trackMode == .chinese {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 7.5, weight: .bold))
                                }
                                Text(player.trackMode.title)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(player.trackMode == .chinese ? AmberTheme.primaryAmber : AmberTheme.labelTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(player.trackMode == .chinese ? AmberTheme.primaryAmber.opacity(0.15) : Color.white.opacity(0.06))
                            )

                            Text(player.currentFeed?.title ?? "")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AmberTheme.labelTertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 4)

                    // 3. Play / Pause Button with Specular Ring
                    Button {
                        player.togglePlayPause()
                        impactFeedback.impactOccurred()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 34, height: 34)
                                .shadow(color: Color.white.opacity(0.2), radius: 6, y: 2)

                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Color.black)
                                .offset(x: player.isPlaying ? 0 : 1)
                        }
                    }
                    .buttonStyle(TactileButtonStyle(scale: 0.90))

                    // 4. Skip forward 30s
                    Button {
                        player.skipForward(30)
                        impactFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(AmberTheme.labelSecondary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(TactileButtonStyle(scale: 0.90))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)

                // 5. Hairline Micro Progress Bar along capsule bottom edge
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
            .liquidGlassCapsule(isPressed: isPressed || isDragging)
            .offset(y: dragOffsetY)
            .scaleEffect(isDragging ? 1.02 : (isPressed ? 0.97 : 1.0))
            .animation(isDragging ? .interactiveSpring() : ForwardMotion.snapSpring, value: dragOffsetY)
            .animation(ForwardMotion.touchDown, value: isPressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onChanged { value in
                        isDragging = true
                        let dy = value.translation.height
                        if dy < 0 {
                            // Upward drag follows finger with light resistance
                            dragOffsetY = dy * 0.82
                        } else {
                            // Downward drag has strong rubber-band resistance
                            dragOffsetY = dy * 0.18
                        }
                    }
                    .onEnded { value in
                        let dy = value.translation.height
                        let predictedY = value.predictedEndTranslation.height
                        if dy < -50 || predictedY < -110 {
                            // Fling or drag upwards triggers fluid full player launch
                            impactFeedback.impactOccurred()
                            withAnimation(ForwardMotion.fluidSheet) {
                                showFullPlayer = true
                                dragOffsetY = 0
                                isDragging = false
                            }
                        } else {
                            // Snap back
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
}

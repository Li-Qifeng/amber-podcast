import SwiftUI

public struct FullPlayerView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @Binding var isPresented: Bool

    // Display tab: 0 = Artwork, 1 = Subtitles/Lyrics, 2 = Shownotes & Notes
    @State private var currentCenterTab: Int = 0
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: Double = 0.0
    @State private var showSpeedSheet: Bool = false

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background: Dynamic vibrant frosted glass matching artwork
                backgroundLayer(geometry: geo)

                VStack(spacing: 0) {
                    // 1. Top Navigation Bar: Drag indicator & Header
                    topHeaderBar

                    // 2. Center Content: Switchable between Artwork, Subtitles, Shownotes
                    centerContentArea(geometry: geo)

                    Spacer(minLength: 12)

                    // 3. Track Mode Pill Selector: [原声 | 中文 | 交替]
                    trackModeSelector
                        .padding(.bottom, 16)

                    // 4. Scrubbing Timeline & Duration
                    timelineScrubberArea
                        .padding(.horizontal, 28)
                        .padding(.bottom, 12)

                    // 5. Main Playback Controls
                    playbackControlsArea
                        .padding(.horizontal, 28)
                        .padding(.bottom, 24)

                    // 6. Bottom Utility Toolbar (Speed, AirPlay, Chapters)
                    bottomUtilityBar
                        .padding(.horizontal, 36)
                        .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? 8 : 20)
                }
            }
        }
        .sheet(isPresented: $showSpeedSheet) {
            speedSelectionSheet
        }
    }

    // MARK: - Dynamic Blurred Background
    private func backgroundLayer(geometry: GeometryProxy) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let coverUrl = player.currentFeed?.coverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .blur(radius: 60)
                        .opacity(0.45)
                        .scaleEffect(1.2)
                } placeholder: {
                    Color.gray.opacity(0.2)
                }
            }

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
    }

    // MARK: - Top Header Bar
    private var topHeaderBar: some View {
        VStack(spacing: 8) {
            // Dismiss grabber pill
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
                .onTapGesture {
                    isPresented = false
                }

            HStack {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                }

                Spacer()

                VStack(spacing: 2) {
                    Text(player.currentFeed?.title ?? "Amber Podcast")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                // Center Tab Switcher (Artwork / Lyrics / Notes)
                HStack(spacing: 12) {
                    tabIconButton(icon: "music.note", tag: 0)
                    tabIconButton(icon: "quote.bubble", tag: 1)
                    tabIconButton(icon: "doc.text", tag: 2)
                }
                .padding(.trailing, 8)
            }
            .padding(.horizontal, 16)
        }
    }

    private func tabIconButton(icon: String, tag: Int) -> some View {
        Button {
            impactFeedback.impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                currentCenterTab = tag
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: currentCenterTab == tag ? .bold : .medium))
                .foregroundStyle(currentCenterTab == tag ? Color.accentColor : Color.secondary)
                .frame(width: 32, height: 32)
                .background(currentCenterTab == tag ? Color.accentColor.opacity(0.15) : Color.clear, in: Circle())
        }
    }

    // MARK: - Center Content
    @ViewBuilder
    private func centerContentArea(geometry: GeometryProxy) -> some View {
        let contentHeight = geometry.size.height * 0.44

        TabView(selection: $currentCenterTab) {
            // Tab 0: Album Artwork with Physical Shadow & Play Scale
            artworkView(size: min(geometry.size.width - 64, contentHeight))
                .tag(0)

            // Tab 1: Live Synced Lyrics & Subtitles
            LyricsSubtitleView()
                .tag(1)

            // Tab 2: Shownotes & AI Markdown Notes
            ShownotesView()
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: contentHeight)
    }

    private func artworkView(size: CGFloat) -> some View {
        VStack {
            Spacer()
            ZStack {
                if let coverUrl = player.currentFeed?.coverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                            .shadow(color: Color.black.opacity(player.isPlaying ? 0.35 : 0.15), radius: player.isPlaying ? 24 : 12, y: player.isPlaying ? 16 : 8)
                            .scaleEffect(player.isPlaying ? 1.0 : 0.88)
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: player.isPlaying)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: size, height: size)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: size, height: size)
                        .overlay(Image(systemName: "mic.fill").font(.system(size: 48)).foregroundStyle(.white))
                }
            }
            Spacer()
        }
    }

    // MARK: - Track Mode Selector Pill Capsule [原声 | 中文 | 交替]
    private var trackModeSelector: some View {
        HStack(spacing: 4) {
            ForEach(TrackMode.allCases, id: \.self) { mode in
                let isSelected = player.trackMode == mode

                Button {
                    player.switchTrackMode(to: mode)
                } label: {
                    HStack(spacing: 6) {
                        if mode == .chinese {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(mode.title)
                            .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.7))
                    .background(
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(LinearGradient(colors: [Color.blue, Color.purple], startPoint: .leading, endPoint: .trailing))
                                    .matchedGeometryEffect(id: "TrackModeSelected", in: namespace)
                                    .shadow(color: Color.purple.opacity(0.3), radius: 6, y: 3)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    @Namespace private var namespace

    // MARK: - Timeline Scrubber Area
    private var timelineScrubberArea: some View {
        let effectiveTime = isScrubbing ? scrubTime : player.currentTime
        let effectiveDuration = max(1.0, player.duration)

        return VStack(spacing: 8) {
            // Interactive Progress Bar
            GeometryReader { barGeo in
                ZStack(alignment: .leading) {
                    // Track Background
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 5)

                    // Active Progress
                    Capsule()
                        .fill(Color.primary)
                        .frame(width: max(0, min(barGeo.size.width, barGeo.size.width * CGFloat(effectiveTime / effectiveDuration))), height: 5)

                    // Scrubber thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: isScrubbing ? 16 : 8, height: isScrubbing ? 16 : 8)
                        .shadow(radius: 4)
                        .offset(x: max(0, min(barGeo.size.width - (isScrubbing ? 16 : 8), barGeo.size.width * CGFloat(effectiveTime / effectiveDuration) - (isScrubbing ? 8 : 4))))
                        .animation(.spring(response: 0.2), value: isScrubbing)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            let progress = max(0.0, min(1.0, Double(value.location.x / barGeo.size.width)))
                            scrubTime = progress * effectiveDuration
                        }
                        .onEnded { _ in
                            player.seek(to: scrubTime)
                            isScrubbing = false
                            impactFeedback.impactOccurred()
                        }
                )
            }
            .frame(height: 16)

            // Time Labels
            HStack {
                Text(formatDuration(effectiveTime))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                Spacer()

                Text("-\(formatDuration(max(0, effectiveDuration - effectiveTime)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Playback Controls
    private var playbackControlsArea: some View {
        VStack(spacing: 16) {
            // Episode Title
            VStack(spacing: 4) {
                Text(player.currentEpisode?.title ?? "未选择节目")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)

                Text(player.currentFeed?.author ?? "")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Buttons: Skip 15s, Play/Pause, Skip 30s
            HStack(spacing: 40) {
                // Skip backward 15s
                Button {
                    player.skipBackward(15)
                    impactFeedback.impactOccurred()
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.primary)
                }

                // Play / Pause Button with Spring Physical Click
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 72, height: 72)
                        .contentShape(Circle())
                }

                // Skip forward 30s
                Button {
                    player.skipForward(30)
                    impactFeedback.impactOccurred()
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(.primary)
                }
            }
        }
    }

    // MARK: - Bottom Utility Bar
    private var bottomUtilityBar: some View {
        HStack {
            // Playback Speed Button
            Button {
                showSpeedSheet = true
            } label: {
                Text(String(format: "%.1fx", player.playbackRate))
                    .font(.subheadline.bold().monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.primary)
            }

            Spacer()

            // Vocal Boost Switch
            Button {
                player.isVocalBoostEnabled.toggle()
                impactFeedback.impactOccurred()
            } label: {
                Image(systemName: player.isVocalBoostEnabled ? "waveform.badge.magnifyingglass" : "waveform")
                    .font(.system(size: 18))
                    .foregroundStyle(player.isVocalBoostEnabled ? Color.accentColor : Color.secondary)
            }

            Spacer()

            // AirPlay route picker button placeholder
            Image(systemName: "airplayaudio")
                .font(.system(size: 18))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Speed Selection Sheet
    private var speedSelectionSheet: some View {
        NavigationStack {
            List {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0], id: \.self) { rate in
                    HStack {
                        Text(String(format: "%.2fx", rate))
                            .font(.body.monospacedDigit())
                        Spacer()
                        if abs(player.playbackRate - Float(rate)) < 0.01 {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        player.setPlaybackRate(Float(rate))
                        showSpeedSheet = false
                    }
                }
            }
            .navigationTitle("播放速度")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    // MARK: - Formatting Helpers
    private func formatDuration(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }
}

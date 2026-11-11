import SwiftUI
import AVKit

public struct FullPlayerView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @Binding var isPresented: Bool

    // Display tab: 0 = Artwork, 1 = Subtitles/Lyrics, 2 = Shownotes & Notes
    @State private var currentCenterTab: Int = 0
    @State private var isScrubbing: Bool = false
    @State private var scrubTime: Double = 0.0
    @State private var showSpeedSheet: Bool = false
    @State private var showNoDualTrackAlert: Bool = false
    @State private var dragOffsetY: CGFloat = 0.0

    @Namespace private var modeNamespace
    @Namespace private var centerTabNamespace
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background: Forward / Apple OLED Ambient Glow Canvas
                ambientBackground(geometry: geo)

                VStack(spacing: 0) {
                    // 1. Top Navigation Bar: Drag indicator & Header
                    topHeaderBar
                        .padding(.top, geo.safeAreaInsets.top > 0 ? 4 : 12)

                    // 2. Center Content Area (Artwork / Lyrics / Shownotes)
                    centerContentArea(geometry: geo)

                    Spacer(minLength: 8)

                    // 3. Track Mode Pill Selector: [原声 | 中文 | 交替]
                    trackModeSelector
                        .padding(.bottom, 14)

                    // 4. Fluid Timeline Scrubber
                    timelineScrubberArea
                        .padding(.horizontal, 28)
                        .padding(.bottom, 14)

                    // 5. Main Playback Controls
                    playbackControlsArea
                        .padding(.horizontal, 28)
                        .padding(.bottom, 20)

                    // 6. Bottom Utility Toolbar (Speed, Vocal Boost, AirPlay)
                    bottomUtilityBar
                        .padding(.horizontal, 36)
                        .padding(.bottom, geo.safeAreaInsets.bottom > 0 ? geo.safeAreaInsets.bottom : 20)
                }
            }
            .offset(y: max(0, dragOffsetY))
            .gesture(
                DragGesture(minimumDistance: 15)
                    .onChanged { value in
                        if value.translation.height > 0 {
                            dragOffsetY = value.translation.height
                        }
                    }
                    .onEnded { value in
                        if value.translation.height > 120 || value.predictedEndTranslation.height > 300 {
                            withAnimation(ForwardMotion.snapSpring) {
                                isPresented = false
                            }
                        } else {
                            withAnimation(ForwardMotion.snapSpring) {
                                dragOffsetY = 0
                            }
                        }
                    }
            )
        }
        .sheet(isPresented: $showSpeedSheet) {
            speedSelectionSheet
        }
        .alert("提示", isPresented: $showNoDualTrackAlert) {
            Button("好", role: .cancel) {}
        } message: {
            Text("当前单集尚未生成 AI 双轨配音与对齐字幕。已为您切换至「字幕」面板，可一键发起极速转译。")
        }
    }

    // MARK: - OLED Ambient Glow Background
    private func ambientBackground(geometry: GeometryProxy) -> some View {
        ZStack {
            AmberTheme.background.ignoresSafeArea()

            if let coverUrl = player.currentFeed?.proxiedCoverUrl, let url = URL(string: coverUrl) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .saturation(1.7)
                        .blur(radius: 90)
                        .opacity(0.42)
                        .scaleEffect(1.25)
                } placeholder: {
                    Color.clear
                }
            }

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.55)
                .ignoresSafeArea()
        }
    }

    // MARK: - Top Header Bar
    private var topHeaderBar: some View {
        VStack(spacing: 6) {
            // Dismiss Grabber Pill
            Capsule()
                .fill(Color.white.opacity(0.30))
                .frame(width: 44, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(ForwardMotion.snapSpring) {
                        isPresented = false
                    }
                }

            HStack(spacing: 12) {
                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AmberTheme.labelSecondary)
                        .frame(width: 36, height: 36)
                        .amberGlass(.circle, isInteractive: true)
                }
                .buttonStyle(TactileButtonStyle(scale: 0.90))

                Spacer()

                // Podcast Channel Title
                VStack(spacing: 2) {
                    Text(player.currentFeed?.title ?? "Amber 播客")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AmberTheme.labelSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Liquid Glass Switcher Tabs: Artwork / Subtitles / Shownotes
                AmberGlassContainer(spacing: 6) {
                    HStack(spacing: 4) {
                        tabPillButton(icon: "music.note", tag: 0)
                        tabPillButton(icon: "quote.bubble.fill", tag: 1)
                        tabPillButton(icon: "text.alignleft", tag: 2)
                    }
                    .padding(3)
                    .amberGlass(.capsule, isInteractive: true)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
        }
    }

    private func tabPillButton(icon: String, tag: Int) -> some View {
        Button {
            impactFeedback.impactOccurred()
            withAnimation(ForwardMotion.snapSpring) {
                currentCenterTab = tag
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12.5, weight: currentCenterTab == tag ? .bold : .medium))
                .foregroundStyle(currentCenterTab == tag ? AmberTheme.labelPrimary : AmberTheme.labelTertiary)
                .frame(width: 32, height: 28)
                .background(
                    ZStack {
                        if currentCenterTab == tag {
                            Capsule()
                                .fill(Color.white.opacity(0.20))
                                .matchedGeometryEffect(id: "CenterTabCapsule", in: centerTabNamespace)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Center Content
    @ViewBuilder
    private func centerContentArea(geometry: GeometryProxy) -> some View {
        let contentHeight = geometry.size.height * 0.44

        TabView(selection: $currentCenterTab) {
            // Tab 0: Physical Breathing Album Artwork
            artworkView(size: min(geometry.size.width - 72, contentHeight))
                .tag(0)

            // Tab 1: Live Synced Dual-Track Subtitles
            LyricsSubtitleView()
                .tag(1)

            // Tab 2: Shownotes & AI Smart Notes
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
                if let coverUrl = player.currentFeed?.proxiedCoverUrl, let url = URL(string: coverUrl) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: AmberTheme.radiusCoverHero, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: AmberTheme.radiusCoverHero, style: .continuous)
                                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
                            )
                            .shadow(color: Color.black.opacity(player.isPlaying ? 0.45 : 0.2),
                                    radius: player.isPlaying ? 28 : 12,
                                    y: player.isPlaying ? 16 : 6)
                            .scaleEffect(player.isPlaying ? 1.0 : 0.90)
                            .animation(ForwardMotion.fluidSheet, value: player.isPlaying)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: AmberTheme.radiusCoverHero, style: .continuous)
                            .fill(Color(white: 0.12))
                            .frame(width: size, height: size)
                    }
                } else {
                    RoundedRectangle(cornerRadius: AmberTheme.radiusCoverHero, style: .continuous)
                        .fill(Color(white: 0.12))
                        .frame(width: size, height: size)
                        .overlay(Image(systemName: "headphones").font(.system(size: 44)).foregroundStyle(.white.opacity(0.6)))
                }
            }
            Spacer()
        }
    }

    // MARK: - Track Mode Selector Pill [原声 | 中文 | 交替]
    private var trackModeSelector: some View {
        HStack(spacing: 2) {
            ForEach(TrackMode.allCases, id: \.self) { mode in
                let isSelected = player.trackMode == mode

                Button {
                    impactFeedback.impactOccurred()
                    if mode != .original && player.timingSegments.isEmpty {
                        withAnimation(ForwardMotion.snapSpring) {
                            currentCenterTab = 1
                        }
                        showNoDualTrackAlert = true
                        return
                    }
                    withAnimation(ForwardMotion.snapSpring) {
                        player.switchTrackMode(to: mode)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Text(mode.title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(isSelected ? AmberTheme.labelPrimary : AmberTheme.labelSecondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        ZStack {
                            if isSelected {
                                Capsule()
                                    .fill(Color.white.opacity(0.22))
                                    .matchedGeometryEffect(id: "TrackModeCapsule", in: modeNamespace)
                                    .shadow(color: Color.black.opacity(0.2), radius: 4, y: 2)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .amberGlass(.capsule, isInteractive: true)
    }

    // MARK: - Fluid Timeline Scrubber Area
    private var timelineScrubberArea: some View {
        let effectiveTime = isScrubbing ? scrubTime : player.currentTime
        let effectiveDuration = max(1.0, player.duration)
        let progress = min(1.0, max(0.0, effectiveTime / effectiveDuration))

        return VStack(spacing: 8) {
            GeometryReader { barGeo in
                ZStack(alignment: .leading) {
                    // Track Background
                    Capsule()
                        .fill(Color.white.opacity(0.15))
                        .frame(height: isScrubbing ? 7 : 4)

                    // Active Glowing Progress
                    Capsule()
                        .fill(player.trackMode == .chinese ? AmberTheme.primaryAmber : Color.white)
                        .frame(width: max(0, min(barGeo.size.width, barGeo.size.width * CGFloat(progress))), height: isScrubbing ? 7 : 4)

                    // Scrubber Thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: isScrubbing ? 14 : 7, height: isScrubbing ? 14 : 7)
                        .shadow(color: Color.black.opacity(0.3), radius: 3, y: 1)
                        .offset(x: max(0, min(barGeo.size.width - (isScrubbing ? 14 : 7), barGeo.size.width * CGFloat(progress) - (isScrubbing ? 7 : 3.5))))
                }
                .frame(height: 18)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            let p = max(0.0, min(1.0, Double(value.location.x / barGeo.size.width)))
                            scrubTime = p * effectiveDuration
                        }
                        .onEnded { _ in
                            player.seek(to: scrubTime)
                            isScrubbing = false
                            impactFeedback.impactOccurred()
                        }
                )
                .animation(ForwardMotion.touchDown, value: isScrubbing)
            }
            .frame(height: 18)

            // Monospaced Time Labels
            HStack {
                Text(formatDuration(effectiveTime))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(AmberTheme.labelTertiary)

                Spacer()

                Text(player.duration > 0 ? "-\(formatDuration(max(0, player.duration - effectiveTime)))" : "--:--")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(AmberTheme.labelTertiary)
            }
        }
    }

    // MARK: - Playback Controls
    private var playbackControlsArea: some View {
        VStack(spacing: 16) {
            // Titles
            VStack(spacing: 4) {
                Text(player.currentEpisode?.title ?? "未选择节目")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)

                Text(player.currentFeed?.author ?? "")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AmberTheme.labelTertiary)
                    .lineLimit(1)
            }

            // Controls: Skip 15s | Play/Pause | Skip 30s
            AmberGlassContainer(spacing: 20) {
                HStack(spacing: 28) {
                    // Skip backward 15s
                    Button {
                        player.skipBackward(15)
                        impactFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "gobackward.15")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AmberTheme.labelPrimary)
                            .frame(width: 52, height: 52)
                            .amberGlass(.circle, isInteractive: true)
                    }
                    .buttonStyle(TactileButtonStyle(scale: 0.94))

                    // Play / Pause Button with Buffering Indicator
                    Button {
                        player.togglePlayPause()
                        impactFeedback.impactOccurred()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 70, height: 70)
                                .shadow(color: Color.black.opacity(0.35), radius: 8, y: 4)

                            if player.isBuffering {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                    .scaleEffect(1.2)
                            } else {
                                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 28, weight: .bold))
                                    .foregroundStyle(Color.black)
                                    .offset(x: player.isPlaying ? 0 : 2)
                            }
                        }
                    }
                    .buttonStyle(TactileButtonStyle(scale: 0.94))

                    // Skip forward 30s
                    Button {
                        player.skipForward(30)
                        impactFeedback.impactOccurred()
                    } label: {
                        Image(systemName: "goforward.30")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(AmberTheme.labelPrimary)
                            .frame(width: 52, height: 52)
                            .amberGlass(.circle, isInteractive: true)
                    }
                    .buttonStyle(TactileButtonStyle(scale: 0.94))
                }
            }
        }
    }

    // MARK: - Bottom Utility Bar
    private var bottomUtilityBar: some View {
        HStack {
            // Apple Podcasts Style Speed Button
            speedButton

            Spacer()

            // Real route picker
            AirPlayRoutePicker()
                .frame(width: 26, height: 26)
        }
    }

    // MARK: - Apple Podcasts Style Speed Button
    private var speedButton: some View {
        Menu {
            ForEach([0.75, 1.0, 1.25, 1.5, 1.75, 2.0], id: \.self) { rate in
                Button {
                    player.setPlaybackRate(Float(rate))
                    impactFeedback.impactOccurred()
                } label: {
                    HStack {
                        Text(formatSpeedText(rate))
                        if abs(player.playbackRate - Float(rate)) < 0.01 {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 2) {
                Text(formatSpeedText(Double(player.playbackRate)))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(AmberTheme.labelPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .amberGlass(.capsule, isInteractive: true)
        } primaryAction: {
            cycleNextSpeed()
        }
        .buttonStyle(TactileButtonStyle(scale: 0.92))
    }

    private func formatSpeedText(_ rate: Double) -> String {
        if rate == floor(rate) {
            return String(format: "%.0f×", rate)
        } else if (rate * 10).truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.1f×", rate)
        } else {
            return String(format: "%.2f×", rate)
        }
    }

    private func cycleNextSpeed() {
        let speeds: [Float] = [1.0, 1.25, 1.5, 1.75, 2.0, 0.75]
        let current = player.playbackRate
        if let idx = speeds.firstIndex(where: { abs($0 - current) < 0.05 }) {
            let nextIdx = (idx + 1) % speeds.count
            player.setPlaybackRate(speeds[nextIdx])
        } else {
            player.setPlaybackRate(1.0)
        }
        impactFeedback.impactOccurred()
    }

    // MARK: - Speed Selection Sheet
    private var speedSelectionSheet: some View {
        NavigationStack {
            List {
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0], id: \.self) { rate in
                    HStack {
                        Text(String(format: "%.2fx", rate))
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .foregroundStyle(AmberTheme.labelPrimary)
                        Spacer()
                        if abs(player.playbackRate - Float(rate)) < 0.01 {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(AmberTheme.primaryAmber)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        player.setPlaybackRate(Float(rate))
                        showSpeedSheet = false
                    }
                    .listRowBackground(AmberTheme.glassSurface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AmberTheme.background)
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

// MARK: - AirPlay Route Picker

private struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = UIColor(AmberTheme.labelTertiary)
        view.activeTintColor = UIColor(AmberTheme.primaryAmber)
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

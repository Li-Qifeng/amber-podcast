import Foundation
import UIKit
import AVFoundation
import MediaPlayer
import Combine

/// Dual-track audio player engine with seamless sentence mapping and bilingual alternating playback
@MainActor
public final class DualTrackAudioPlayer: ObservableObject {
    public static let shared = DualTrackAudioPlayer()

    // MARK: - Published State
    @Published public var currentEpisode: Episode?
    @Published public var currentFeed: PodcastFeed?
    @Published public var isPlaying: Bool = false
    @Published public var isBuffering: Bool = false
    @Published public var currentTime: Double = 0.0          // In current track's timeline (seconds)
    @Published public var duration: Double = 0.0             // Duration of current track (seconds)
    @Published public var trackMode: TrackMode = TrackMode(
        rawValue: UserDefaults.standard.string(forKey: "amber_default_track_mode") ?? ""
    ) ?? .chinese
    @Published public var playbackRate: Float = 1.0          // 0.5x to 3.0x

    /// Backend progress sync runs on a timer while playing, and once on pause,
    /// stop and track switch. Before this the endpoint existed but was never
    /// called, so "继续收听" always showed 0%.
    private var progressTimer: Timer?
    @Published public var isVocalBoostEnabled: Bool = false
    @Published public var currentSegmentIndex: Int = 0

    // Alignment and artifacts
    @Published public var timingSegments: [TimingSegment] = []
    @Published public var fullMapping: [FullMappingSegment] = []
    @Published public var chapters: [Chapter] = []
    @Published public var articleMarkdown: String = ""

    // MARK: - Private Players
    private var originalPlayer: AVPlayer?
    private var chinesePlayer: AVPlayer?
    private var originalTimeObserverToken: Any?
    private var chineseTimeObserverToken: Any?
    private var originalStatusObserver: NSKeyValueObservation?
    private var chineseStatusObserver: NSKeyValueObservation?
    private var isAlternatingPlayingEn: Bool = true
    private var isSeekingOptimisticLock: Bool = false
    private var hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    private init() {
        configureAudioSession()
        setupRemoteCommands()
    }

    // MARK: - Audio Session Setup
    private func configureAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetooth, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch {
            print("Failed to configure AVAudioSession: \(error)")
        }
    }

    #if DEBUG
    /// Seeds a now-playing state so CI can screenshot the mini player and its
    /// shared glass field with the dock. Never compiled into release builds.
    public func seedDemoNowPlaying() {
        guard currentEpisode == nil else { return }
        currentEpisode = Episode.samples.first
        currentFeed = PodcastFeed.samples.first
        currentTime = 92
        duration = 1800
    }
    #endif

    // MARK: - Load & Play Episode
    public func loadEpisode(
        episode: Episode,
        feed: PodcastFeed,
        artifacts: EpisodeArtifacts?,
        autoPlay: Bool = true
    ) {
        // Teardown existing players
        stop()

        self.currentEpisode = episode
        self.currentFeed = feed
        self.timingSegments = artifacts?.timingSync ?? []
        self.fullMapping = artifacts?.fullMapping ?? []
        self.chapters = artifacts?.chapters ?? []
        self.articleMarkdown = artifacts?.articleMarkdown ?? ""

        // If no Chinese dual-track artifacts exist for this episode, force original track
        if self.timingSegments.isEmpty {
            self.trackMode = .original
        }

        // 1. Prepare original audio player
        if let originalUrl = URL(string: episode.audioUrl) {
            let item = AVPlayerItem(url: originalUrl)
            self.originalPlayer = AVPlayer(playerItem: item)
            self.originalPlayer?.automaticallyWaitsToMinimizeStalling = true
        }

        // 2. Prepare Chinese audio player ONLY IF timing sync / artifacts exist
        if !self.timingSegments.isEmpty {
            let streamEndpoint = artifacts?.streaming.streamEndpoint ?? "/api/v1/episodes/\(episode.id)/stream/chinese"
            let fullStreamUrlString: String
            if streamEndpoint.lowercased().hasPrefix("http://") || streamEndpoint.lowercased().hasPrefix("https://") {
                fullStreamUrlString = streamEndpoint
            } else {
                let base = AmberAPIClient.shared.serverBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let endpoint = streamEndpoint.hasPrefix("/") ? streamEndpoint : "/\(streamEndpoint)"
                fullStreamUrlString = "\(base)\(endpoint)"
            }
            if let zhUrl = URL(string: fullStreamUrlString) {
                let item = AVPlayerItem(url: zhUrl)
                self.chinesePlayer = AVPlayer(playerItem: item)
                self.chinesePlayer?.automaticallyWaitsToMinimizeStalling = true
            }
        } else {
            self.chinesePlayer = nil
        }

        // Attach periodic time observer to the active player
        attachTimeObserver()

        restoreProgress(episodeId: episode.id)

        if autoPlay {
            self.isBuffering = true
            play()
        }

        updateNowPlayingInfo()
    }

    // MARK: - Active Player Helper
    private var activePlayer: AVPlayer? {
        switch trackMode {
        case .original:
            return originalPlayer
        case .chinese:
            return chinesePlayer ?? originalPlayer
        case .alternating:
            return isAlternatingPlayingEn ? originalPlayer : (chinesePlayer ?? originalPlayer)
        }
    }

    // MARK: - Playback Control
    public func play() {
        try? AVAudioSession.sharedInstance().setActive(true)
        guard let player = activePlayer else { return }
        if player.timeControlStatus != .playing {
            isBuffering = true
        }
        player.play()
        player.rate = playbackRate
        isPlaying = true
        hapticFeedback.impactOccurred()
        updateNowPlayingInfo()
        startProgressSync()
    }

    public func pause() {
        originalPlayer?.pause()
        chinesePlayer?.pause()
        isPlaying = false
        isBuffering = false
        hapticFeedback.impactOccurred()
        updateNowPlayingInfo()
        stopProgressSync()
        flushProgress()
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func stop() {
        pause()
        removeTimeObserver()
        originalPlayer = nil
        chinesePlayer = nil
        currentTime = 0.0
        duration = 0.0
    }

    // MARK: - Progress Sync
    private func startProgressSync() {
        guard progressTimer == nil else { return }
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.flushProgress() }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressSync() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    public func flushProgress(finished: Bool = false) {
        guard let episode = currentEpisode else { return }
        let position = Int((currentTime * 1000).rounded())
        let total = Int((max(duration, currentTime) * 1000).rounded())
        guard total > 0 else { return }
        Task {
            await AmberAPIClient.shared.syncProgress(
                episodeId: episode.id,
                positionMs: position,
                durationMs: total,
                trackMode: trackMode,
                isFinished: finished
            )
        }
    }

    /// Restores the last saved position. Called after the players are built so a
    /// reopened episode resumes instead of starting at 0:00.
    public func restoreProgress(episodeId: String) {
        Task {
            guard let saved = try? await AmberAPIClient.shared.fetchProgress(episodeId: episodeId),
                  saved.positionMs > 5_000,
                  !saved.isComplete else { return }
            let seconds = Double(saved.positionMs) / 1000.0
            await MainActor.run {
                guard self.currentEpisode?.id == episodeId else { return }
                self.seek(to: seconds)
            }
        }
    }

    // MARK: - Instant Zero-Gap Track Switching
    public func switchTrackMode(to newMode: TrackMode) {
        guard newMode != self.trackMode else { return }
        hapticFeedback.impactOccurred()

        let wasPlaying = self.isPlaying
        let prevMode = self.trackMode
        let curTime = self.currentTime

        // Find current sentence index in timing segments
        let matchingIndex = findSegmentIndex(forTime: curTime, inMode: prevMode)
        self.trackMode = newMode

        // Pause previous
        originalPlayer?.pause()
        chinesePlayer?.pause()

        if let segIndex = matchingIndex, segIndex < timingSegments.count {
            let seg = timingSegments[segIndex]
            let targetTime: Double
            switch newMode {
            case .original:
                targetTime = seg.en.start
            case .chinese:
                targetTime = seg.zh.start
            case .alternating:
                targetTime = seg.en.start
                isAlternatingPlayingEn = true
            }
            seek(to: targetTime)
        } else {
            // Fallback: keep current elapsed time if no timing sync data
            seek(to: curTime)
        }

        if wasPlaying {
            play()
        }

        updateNowPlayingInfo()
    }

    // MARK: - Seek with Optimistic Time Lock
    public func seek(to seconds: Double) {
        guard let player = activePlayer else { return }
        let targetCMTime = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        
        self.isSeekingOptimisticLock = true
        self.currentTime = seconds
        
        player.seek(to: targetCMTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                self?.isSeekingOptimisticLock = false
            }
        }
        updateNowPlayingInfo()
    }

    public func skipForward(_ seconds: Double = 30.0) {
        seek(to: currentTime + seconds)
    }

    public func skipBackward(_ seconds: Double = 15.0) {
        seek(to: max(0, currentTime - seconds))
    }

    public func setPlaybackRate(_ rate: Float) {
        self.playbackRate = rate
        if isPlaying {
            activePlayer?.rate = rate
        }
        updateNowPlayingInfo()
    }

    // MARK: - Segment Lookup
    public func findSegmentIndex(forTime time: Double, inMode mode: TrackMode) -> Int? {
        guard !timingSegments.isEmpty else { return nil }
        for (idx, seg) in timingSegments.enumerated() {
            let range = (mode == .original || (mode == .alternating && isAlternatingPlayingEn)) ? seg.en : seg.zh
            if time >= range.start && time <= range.end {
                return idx
            }
        }
        // Fallback closest
        return timingSegments.enumerated().min(by: { a, b in
            let rA = (mode == .original) ? a.element.en : a.element.zh
            let rB = (mode == .original) ? b.element.en : b.element.zh
            return abs(rA.start - time) < abs(rB.start - time)
        })?.offset
    }

    // MARK: - Time Observer & Alternating Mode Logic
    private func attachTimeObserver() {
        removeTimeObserver()
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)

        // 1. Observer for original audio player
        originalTimeObserverToken = originalPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let shouldProcess = (self.trackMode == .original) || (self.trackMode == .alternating && self.isAlternatingPlayingEn)
            guard shouldProcess else { return }
            self.handlePeriodicTimeTick(time: time, isFromEnglish: true)
        }

        // 2. Observer for Chinese audio player
        chineseTimeObserverToken = chinesePlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let shouldProcess = (self.trackMode == .chinese) || (self.trackMode == .alternating && !self.isAlternatingPlayingEn)
            guard shouldProcess else { return }
            self.handlePeriodicTimeTick(time: time, isFromEnglish: false)
        }

        // 3. Status observers to detect network stream buffering
        originalStatusObserver = originalPlayer?.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            guard let self = self, self.trackMode == .original || (self.trackMode == .alternating && self.isAlternatingPlayingEn) else { return }
            self.updateBufferingState(for: player)
        }
        chineseStatusObserver = chinesePlayer?.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            guard let self = self, self.trackMode == .chinese || (self.trackMode == .alternating && !self.isAlternatingPlayingEn) else { return }
            self.updateBufferingState(for: player)
        }
    }

    private func handlePeriodicTimeTick(time: CMTime, isFromEnglish: Bool) {
        guard !isSeekingOptimisticLock else { return }
        let sec = time.seconds
        guard !sec.isNaN else { return }
        self.currentTime = sec

        // Update duration
        if let item = self.activePlayer?.currentItem, item.duration.seconds > 0, !item.duration.seconds.isNaN {
            self.duration = item.duration.seconds
        }

        // Update current segment index
        if let idx = self.findSegmentIndex(forTime: sec, inMode: self.trackMode) {
            self.currentSegmentIndex = idx

            // Alternating Playback Logic
            if self.trackMode == .alternating && idx < self.timingSegments.count {
                let seg = self.timingSegments[idx]
                if self.isAlternatingPlayingEn && isFromEnglish && sec >= seg.en.end {
                    // Switch from English sentence to Chinese sentence
                    self.isAlternatingPlayingEn = false
                    self.originalPlayer?.pause()
                    self.chinesePlayer?.seek(to: CMTime(seconds: seg.zh.start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                    self.chinesePlayer?.rate = self.playbackRate
                } else if !self.isAlternatingPlayingEn && !isFromEnglish && sec >= seg.zh.end {
                    // Switch to next English sentence
                    if idx + 1 < self.timingSegments.count {
                        let nextSeg = self.timingSegments[idx + 1]
                        self.isAlternatingPlayingEn = true
                        self.chinesePlayer?.pause()
                        self.originalPlayer?.seek(to: CMTime(seconds: nextSeg.en.start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                        self.originalPlayer?.rate = self.playbackRate
                    }
                }
            }
        }
    }

    private func updateBufferingState(for player: AVPlayer) {
        Task { @MainActor in
            if player.timeControlStatus == .waitingToPlayAtSpecifiedRate && self.isPlaying {
                self.isBuffering = true
            } else if player.timeControlStatus == .playing {
                self.isBuffering = false
            }
        }
    }

    private func removeTimeObserver() {
        if let token = originalTimeObserverToken {
            originalPlayer?.removeTimeObserver(token)
            originalTimeObserverToken = nil
        }
        if let token = chineseTimeObserverToken {
            chinesePlayer?.removeTimeObserver(token)
            chineseTimeObserverToken = nil
        }
        originalStatusObserver?.invalidate()
        originalStatusObserver = nil
        chineseStatusObserver?.invalidate()
        chineseStatusObserver = nil
    }

    // MARK: - Lock Screen & Control Center
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            self?.play()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        center.skipForwardCommand.preferredIntervals = [30]
        center.skipForwardCommand.addTarget { [weak self] _ in
            self?.skipForward(30)
            return .success
        }
        center.skipBackwardCommand.preferredIntervals = [15]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            self?.skipBackward(15)
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let posEvent = event as? MPChangePlaybackPositionCommandEvent {
                self?.seek(to: posEvent.positionTime)
                return .success
            }
            return .commandFailed
        }
    }

    private func updateNowPlayingInfo() {
        guard let episode = currentEpisode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyArtist: currentFeed?.title ?? "Amber Podcast",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration > 0 ? duration : Double(episode.duration),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0
        ]

        // Load cover art async without blocking threads
        if let coverUrlStr = currentFeed?.coverUrl, let url = URL(string: coverUrlStr) {
            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let image = UIImage(data: data) {
                        await MainActor.run {
                            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                            var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? info
                            updatedInfo[MPMediaItemPropertyArtwork] = artwork
                            MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
                        }
                    }
                } catch {
                    // Ignore transient network errors
                }
            }
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

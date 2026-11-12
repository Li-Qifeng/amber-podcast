import Foundation

public final class AmberAPIClient: ObservableObject {
    public static let shared = AmberAPIClient()

    @Published public var serverBaseUrl: String {
        didSet {
            UserDefaults.standard.set(serverBaseUrl, forKey: "amber_server_url")
        }
    }

    @Published public var authToken: String {
        didSet {
            UserDefaults.standard.set(authToken, forKey: "amber_auth_token")
        }
    }

    private let session: URLSession

    private init() {
        self.serverBaseUrl = UserDefaults.standard.string(forKey: "amber_server_url") ?? "https://podcast.refoxai.com"
        self.authToken = UserDefaults.standard.string(forKey: "amber_auth_token") ?? "amber-secret-token-2026"
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        self.session = URLSession(configuration: config)
    }

    private func makeRequest(endpoint: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        let base = serverBaseUrl.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanEndpoint = endpoint.hasPrefix("/") ? endpoint : "/\(endpoint)"
        guard let url = URL(string: "\(base)\(cleanEndpoint)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }

    // MARK: - Health Check
    public struct HealthResponse: Codable {
        public let status: String?
        public let app: String?
        public let version: String?
    }

    public func checkHealth(customUrl: String? = nil) async -> (ok: Bool, message: String) {
        let base = (customUrl ?? serverBaseUrl).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/health") else {
            return (false, "无效的服务器地址")
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 8.0
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
                return (false, "网关响应异常 (HTTP \(code))")
            }
            if let decoded = try? JSONDecoder().decode(HealthResponse.self, from: data) {
                let ver = decoded.version ?? "0.1.0"
                let app = decoded.app ?? "amber-podcast"
                return (true, "服务正常 (\(app) v\(ver))")
            }
            return (true, "网关连通正常")
        } catch {
            return (false, "连接失败: \(error.localizedDescription)")
        }
    }

    // MARK: - Search
    public func searchPodcasts(query: String) async throws -> [PodcastFeed] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard var components = URLComponents(string: "\(serverBaseUrl)/api/v1/search") else {
            throw URLError(.badURL)
        }
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        guard let url = components.url else { throw URLError(.badURL) }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, resp) = try await session.data(for: req)
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct SearchResponse: Codable {
            let results: [PodcastFeed]
        }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.results
    }

    // MARK: - Discover Feed
    public struct DiscoverFeedResponse: Codable {
        public let featured: [PodcastFeed]
        public let topChinese: [PodcastFeed]
        public let topGlobal: [PodcastFeed]

        public init(featured: [PodcastFeed], topChinese: [PodcastFeed], topGlobal: [PodcastFeed]) {
            self.featured = featured
            self.topChinese = topChinese
            self.topGlobal = topGlobal
        }

        enum CodingKeys: String, CodingKey {
            case featured
            case topChinese = "top_chinese"
            case topGlobal = "top_global"
        }
    }

    public func fetchDiscoverFeed() async throws -> DiscoverFeedResponse {
        let req = try makeRequest(endpoint: "/api/v1/discover")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(DiscoverFeedResponse.self, from: data)
    }

    // MARK: - Library
    public struct LibraryResponse: Codable {
        public let feeds: [PodcastFeed]
        public let recentEpisodes: [Episode]
        /// Newest episode published after its feed was subscribed. Null when no
        /// new drop has landed yet — the home screen collapses the hero then.
        public let heroEpisode: Episode?

        public init(feeds: [PodcastFeed], recentEpisodes: [Episode], heroEpisode: Episode? = nil) {
            self.feeds = feeds
            self.recentEpisodes = recentEpisodes
            self.heroEpisode = heroEpisode
        }

        enum CodingKeys: String, CodingKey {
            case feeds
            case recentEpisodes = "recent_episodes"
            case heroEpisode = "hero_episode"
        }
    }

    public func fetchLibrary() async throws -> LibraryResponse {
        let req = try makeRequest(endpoint: "/api/v1/library")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(LibraryResponse.self, from: data)
    }

    // MARK: - Pipeline Settings

    public struct PipelineSettingsResponse: Codable {
        public let settings: [String: String]
    }

    public func fetchPipelineSettings() async throws -> [String: String] {
        let req = try makeRequest(endpoint: "/api/v1/settings")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(PipelineSettingsResponse.self, from: data).settings
    }

    public func updatePipelineSettings(_ updates: [String: String]) async throws -> [String: String] {
        let body = try JSONEncoder().encode(updates)
        let req = try makeRequest(endpoint: "/api/v1/settings", method: "PUT", body: body)
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(PipelineSettingsResponse.self, from: data).settings
    }

    // MARK: - Pipeline Status (Dump & Transcription Telemetry)
    public struct PipelineStatusSummary: Codable {
        public let activeCount: Int
        public let readyCount: Int
        public let failedCount: Int
        public let idleCount: Int
        public let storageMb: Double
        public let asrEngine: String
        public let ttsEngine: String
        public let serverStatus: String
        public let llmEngine: String?

        enum CodingKeys: String, CodingKey {
            case activeCount = "active_count"
            case readyCount = "ready_count"
            case failedCount = "failed_count"
            case idleCount = "idle_count"
            case storageMb = "storage_mb"
            case asrEngine = "asr_engine"
            case ttsEngine = "tts_engine"
            case serverStatus = "server_status"
            case llmEngine = "llm_engine"
        }
    }

    public struct PipelineFeedGroup: Codable, Identifiable {
        public let feedId: String
        public let feedTitle: String
        public let coverUrl: String
        public let episodes: [Episode]

        public var id: String { feedId }

        enum CodingKeys: String, CodingKey {
            case feedId = "feed_id"
            case feedTitle = "feed_title"
            case coverUrl = "cover_url"
            case episodes
        }
    }

    public struct PipelineStatusResponse: Codable {
        public let summary: PipelineStatusSummary
        public let feeds: [PipelineFeedGroup]
        public let activeTasks: [Episode]
        public let recentCompleted: [Episode]
        public let failedTasks: [Episode]

        enum CodingKeys: String, CodingKey {
            case summary
            case feeds
            case activeTasks = "active_tasks"
            case recentCompleted = "recent_completed"
            case failedTasks = "failed_tasks"
        }
    }

    public func fetchPipelineStatus() async throws -> PipelineStatusResponse {
        let req = try makeRequest(endpoint: "/api/v1/pipeline/status")
        let (data, resp) = try await session.data(for: req)
        guard let httpResp = resp as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(PipelineStatusResponse.self, from: data)
    }

    // MARK: - Pipeline Console (queue / stats / actions)

    public struct PipelineTaskCard: Codable, Identifiable {
        public let episodeId: String
        public let title: String
        public let feedId: String
        public let feedTitle: String
        public let coverUrl: String
        public let status: String
        public let progress: Int
        public let errorMessage: String
        public let elapsedSec: Int
        public let updatedAt: Int

        public var id: String { episodeId }

        enum CodingKeys: String, CodingKey {
            case episodeId = "episode_id"
            case title
            case feedId = "feed_id"
            case feedTitle = "feed_title"
            case coverUrl = "cover_url"
            case status, progress
            case errorMessage = "error_message"
            case elapsedSec = "elapsed_sec"
            case updatedAt = "updated_at"
        }

        /// Human-readable duration; "—" when the backend has no real start stamp.
        public var elapsedText: String {
            guard elapsedSec > 0 else { return "—" }
            let m = elapsedSec / 60
            let s = elapsedSec % 60
            if m >= 60 { return "\(m / 60)h\(m % 60)m" }
            return m > 0 ? "\(m)m\(s)s" : "\(s)s"
        }
    }

    public struct PipelineQueueCounts: Codable {
        public let running: Int
        public let queued: Int
        public let failed: Int
        public let completed: Int
    }

    public struct PipelineQueueResponse: Codable {
        public let running: [PipelineTaskCard]
        public let queued: [PipelineTaskCard]
        public let failed: [PipelineTaskCard]
        public let completed: [PipelineTaskCard]
        public let counts: PipelineQueueCounts
    }

    public struct PipelineTrendPoint: Codable, Identifiable {
        public let date: String
        public let count: Int
        public var id: String { date }
    }

    public struct PipelineStatsResponse: Codable {
        public let todayDumped: Int
        public let avgDurationSec: Int
        public let successRate: Double
        public let totalReady: Int
        public let totalFailed: Int
        public let trend: [PipelineTrendPoint]

        enum CodingKeys: String, CodingKey {
            case todayDumped = "today_dumped"
            case avgDurationSec = "avg_duration_sec"
            case successRate = "success_rate"
            case totalReady = "total_ready"
            case totalFailed = "total_failed"
            case trend
        }
    }

    public struct BatchTranslateResponse: Codable {
        public let queued: Int
        public let skipped: Int
        public let totalRequested: Int

        enum CodingKeys: String, CodingKey {
            case queued, skipped
            case totalRequested = "total_requested"
        }
    }

    public func fetchPipelineQueue() async throws -> PipelineQueueResponse {
        let req = try makeRequest(endpoint: "/api/v1/pipeline/queue")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(PipelineQueueResponse.self, from: data)
    }

    public func fetchPipelineStats() async throws -> PipelineStatsResponse {
        let req = try makeRequest(endpoint: "/api/v1/pipeline/stats")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(PipelineStatsResponse.self, from: data)
    }

    public func batchTranslate(
        episodeIds: [String] = [],
        feedId: String? = nil,
        onlyIdle: Bool = true
    ) async throws -> BatchTranslateResponse {
        var payload: [String: Any] = ["only_idle": onlyIdle]
        if let feedId = feedId { payload["feed_id"] = feedId }
        if !episodeIds.isEmpty { payload["episode_ids"] = episodeIds }
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let req = try makeRequest(endpoint: "/api/v1/pipeline/batch-translate", method: "POST", body: bodyData)
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(BatchTranslateResponse.self, from: data)
    }

    public func cancelEpisodeTask(episodeId: String) async throws {
        let req = try makeRequest(endpoint: "/api/v1/episodes/\(episodeId)/cancel", method: "POST")
        let (_, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    public func deleteEpisodeArtifacts(episodeId: String) async throws {
        let req = try makeRequest(endpoint: "/api/v1/episodes/\(episodeId)/artifacts", method: "DELETE")
        let (_, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Feeds
    public func subscribe(url: String, autoTranslate: Bool = false) async throws {
        struct SubBody: Codable {
            let url: String
            let auto_translate: Bool
        }
        let bodyData = try JSONEncoder().encode(SubBody(url: url, auto_translate: autoTranslate))
        let req = try makeRequest(endpoint: "/api/v1/feeds/subscribe", method: "POST", body: bodyData)
        let (_, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    public func listFeeds() async throws -> [PodcastFeed] {
        let req = try makeRequest(endpoint: "/api/v1/feeds")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct ListFeedsResponse: Codable {
            let feeds: [PodcastFeed]
        }
        let decoded = try JSONDecoder().decode(ListFeedsResponse.self, from: data)
        return decoded.feeds
    }

    public func deleteFeed(feedId: String) async throws {
        let req = try makeRequest(endpoint: "/api/v1/feeds/\(feedId)", method: "DELETE")
        let (_, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Episodes
    public func listEpisodes(feedId: String, feedUrl: String? = nil) async throws -> [Episode] {
        var ep = "/api/v1/feeds/\(feedId)/episodes"
        if let feedUrl = feedUrl, !feedUrl.isEmpty, let enc = feedUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            ep += "?feed_url=\(enc)"
        }
        let req = try makeRequest(endpoint: ep)
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct ListEpisodesResponse: Codable {
            let episodes: [Episode]
        }
        let decoded = try JSONDecoder().decode(ListEpisodesResponse.self, from: data)
        return decoded.episodes
    }

    public func getEpisode(episodeId: String) async throws -> Episode {
        let req = try makeRequest(endpoint: "/api/v1/episodes/\(episodeId)")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct EpDetailResponse: Codable {
            let episode: Episode
        }
        let decoded = try JSONDecoder().decode(EpDetailResponse.self, from: data)
        return decoded.episode
    }

    // MARK: - Translation Trigger
    public func triggerTranslation(episodeId: String) async throws {
        let req = try makeRequest(endpoint: "/api/v1/episodes/\(episodeId)/translate", method: "POST")
        let (_, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    public func triggerTranslation(episode: Episode, feed: PodcastFeed? = nil) async throws {
        var req = try makeRequest(endpoint: "/api/v1/episodes/\(episode.id)/translate", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [
            "episode": [
                "id": episode.id,
                "feed_id": episode.feedId,
                "title": episode.title,
                "audio_url": episode.audioUrl,
                "duration": episode.duration,
                "pub_date": episode.pubDate,
                "shownotes": episode.shownotes
            ]
        ]
        if let f = feed {
            payload["feed"] = [
                "id": f.id,
                "title": f.title,
                "author": f.author,
                "cover_url": f.coverUrl,
                "feed_url": f.feedUrl
            ]
        }
        if let body = try? JSONSerialization.data(withJSONObject: payload) {
            req.httpBody = body
        }
        let (_, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Artifacts
    public func fetchArtifacts(episodeId: String) async throws -> EpisodeArtifacts {
        let req = try makeRequest(endpoint: "/api/v1/episodes/\(episodeId)/artifacts")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(EpisodeArtifacts.self, from: data)
    }


    // MARK: - Playback Progress Read
    /// Server shape: `{"episode_id": ..., "playback_progress": {row}|null}`
    /// where the row codes `is_finished` as 0/1.
    public struct PlaybackProgress: Codable {
        public let episodeId: String
        public let positionMs: Int
        public let durationMs: Int
        public let trackMode: String
        public let isFinished: Int

        enum CodingKeys: String, CodingKey {
            case episodeId = "episode_id"
            case positionMs = "position_ms"
            case durationMs = "duration_ms"
            case trackMode = "track_mode"
            case isFinished = "is_finished"
        }

        public var isComplete: Bool { isFinished == 1 }
    }

    private struct ProgressEnvelope: Codable {
        let playbackProgress: PlaybackProgress?

        enum CodingKeys: String, CodingKey {
            case playbackProgress = "playback_progress"
        }
    }

    public func fetchProgress(episodeId: String) async throws -> PlaybackProgress? {
        let req = try makeRequest(endpoint: "/api/v1/playback/progress/\(episodeId)")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(ProgressEnvelope.self, from: data).playbackProgress
    }

    // MARK: - Playback Progress Sync
    public func syncProgress(episodeId: String, positionMs: Int, durationMs: Int, trackMode: TrackMode, isFinished: Bool) async {
        struct ProgressPayload: Codable {
            let episode_id: String
            let position_ms: Int
            let duration_ms: Int
            let track_mode: String
            let is_finished: Bool
        }
        let payload = ProgressPayload(
            episode_id: episodeId,
            position_ms: positionMs,
            duration_ms: durationMs,
            track_mode: trackMode.rawValue,
            is_finished: isFinished
        )
        guard let bodyData = try? JSONEncoder().encode(payload) else { return }
        guard let req = try? makeRequest(endpoint: "/api/v1/playback/progress", method: "POST", body: bodyData) else { return }
        _ = try? await session.data(for: req)
    }
}

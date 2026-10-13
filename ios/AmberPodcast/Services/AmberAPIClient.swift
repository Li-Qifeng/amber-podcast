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
        guard let url = URL(string: "\(serverBaseUrl)\(endpoint)") else {
            throw URLError(.badURL)
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }

    // MARK: - Search
    public func searchPodcasts(query: String) async throws -> [PodcastFeed] {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let req = try makeRequest(endpoint: "/api/v1/search?q=\(encoded)")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        struct SearchResponse: Codable {
            let results: [PodcastFeed]
        }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.results
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
    public func listEpisodes(feedId: String) async throws -> [Episode] {
        let req = try makeRequest(endpoint: "/api/v1/feeds/\(feedId)/episodes")
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

    // MARK: - Artifacts
    public func fetchArtifacts(episodeId: String) async throws -> EpisodeArtifacts {
        let req = try makeRequest(endpoint: "/api/v1/episodes/\(episodeId)/artifacts")
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(EpisodeArtifacts.self, from: data)
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

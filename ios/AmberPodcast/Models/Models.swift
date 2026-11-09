import Foundation

// MARK: - Track Mode
public enum TrackMode: String, Codable, CaseIterable {
    case original = "original"         // 英文原声
    case chinese = "chinese"           // AI 中文配音
    case alternating = "alternating"   // 双语交替跟读模式 (先原声再中文)

    public var title: String {
        switch self {
        case .original: return "原声"
        case .chinese: return "中文"
        case .alternating: return "交替"
        }
    }
}

// MARK: - Podcast Feed
public struct PodcastFeed: Identifiable, Codable, Hashable {
    public let id: String
    public let sourceType: String       // "apple_rss" or "xiaoyuzhou"
    public let title: String
    public let author: String
    public let feedUrl: String
    public let coverUrl: String
    public let description: String
    public var autoTranslate: Int       // 0 or 1
    public var editorialTag: String?
    public var genre: String?
    public var trackCount: Int?

    public var proxiedCoverUrl: String {
        guard !coverUrl.isEmpty else { return "" }
        if coverUrl.contains("refoxai.com") { return coverUrl }
        guard let encoded = coverUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return coverUrl
        }
        return "\(AmberAPIClient.shared.serverBaseUrl)/api/v1/images/proxy?url=\(encoded)&w=1200"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case collectionId = "collection_id"
        case sourceType = "source_type"
        case title, author
        case feedUrl = "feed_url"
        case coverUrl = "cover_url"
        case description
        case autoTranslate = "auto_translate"
        case editorialTag = "editorial_tag"
        case genre
        case trackCount = "track_count"
    }

    public init(
        id: String,
        sourceType: String,
        title: String,
        author: String,
        feedUrl: String,
        coverUrl: String,
        description: String,
        autoTranslate: Int = 0,
        editorialTag: String? = nil,
        genre: String? = nil,
        trackCount: Int? = nil
    ) {
        self.id = id
        self.sourceType = sourceType
        self.title = title
        self.author = author
        self.feedUrl = feedUrl
        self.coverUrl = coverUrl
        self.description = description
        self.autoTranslate = autoTranslate
        self.editorialTag = editorialTag
        self.genre = genre
        self.trackCount = trackCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let directId = try? container.decode(String.self, forKey: .id), !directId.isEmpty {
            self.id = directId
        } else if let collId = try? container.decode(String.self, forKey: .collectionId), !collId.isEmpty {
            self.id = collId
        } else if let collInt = try? container.decode(Int.self, forKey: .collectionId) {
            self.id = String(collInt)
        } else {
            self.id = UUID().uuidString
        }
        self.sourceType = (try? container.decode(String.self, forKey: .sourceType)) ?? "apple_rss"
        self.title = (try? container.decode(String.self, forKey: .title)) ?? ""
        self.author = (try? container.decode(String.self, forKey: .author)) ?? ""
        self.feedUrl = (try? container.decode(String.self, forKey: .feedUrl)) ?? ""
        self.coverUrl = (try? container.decode(String.self, forKey: .coverUrl)) ?? ""
        self.description = (try? container.decode(String.self, forKey: .description)) ?? ""
        self.autoTranslate = (try? container.decode(Int.self, forKey: .autoTranslate)) ?? 0
        self.editorialTag = try? container.decode(String.self, forKey: .editorialTag)
        self.genre = try? container.decode(String.self, forKey: .genre)
        self.trackCount = try? container.decode(Int.self, forKey: .trackCount)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceType, forKey: .sourceType)
        try container.encode(title, forKey: .title)
        try container.encode(author, forKey: .author)
        try container.encode(feedUrl, forKey: .feedUrl)
        try container.encode(coverUrl, forKey: .coverUrl)
        try container.encode(description, forKey: .description)
        try container.encode(autoTranslate, forKey: .autoTranslate)
        try container.encodeIfPresent(editorialTag, forKey: .editorialTag)
        try container.encodeIfPresent(genre, forKey: .genre)
        try container.encodeIfPresent(trackCount, forKey: .trackCount)
    }
}

// MARK: - Sample Preview Data
public extension PodcastFeed {
    static let samples: [PodcastFeed] = [
        PodcastFeed(
            id: "feed_huberman",
            sourceType: "apple_rss",
            title: "Huberman Lab",
            author: "Dr. Andrew Huberman",
            feedUrl: "https://feeds.megaphone.fm/hubermanlab",
            coverUrl: "https://images.unsplash.com/photo-1518770660439-4636190af475?w=800&auto=format&fit=crop&q=80",
            description: "Neural pathways, dopamine architecture and daily cognitive protocols.",
            autoTranslate: 1
        ),
        PodcastFeed(
            id: "feed_lex",
            sourceType: "apple_rss",
            title: "Lex Fridman Podcast",
            author: "Lex Fridman",
            feedUrl: "https://lexfridman.com/feed/podcast/",
            coverUrl: "https://images.unsplash.com/photo-1618005182384-a83a8bd57fbe?w=800&auto=format&fit=crop&q=80",
            description: "Conversations about AI, science, technology, history, and consciousness.",
            autoTranslate: 1
        )
    ]
}

public extension Episode {
    static let samples: [Episode] = [
        Episode(
            id: "ep_huberman_dopamine",
            feedId: "feed_huberman",
            guid: "huberman_001",
            title: "How to Optimize Your Dopamine & Sustained Motivation",
            audioUrl: "https://traffic.megaphone.fm/GLT3547289871.mp3",
            duration: 5240,
            pubDate: "2026-10-12",
            shownotes: "In this episode, Dr. Huberman discusses the biological mechanisms of dopamine, motivation peaks, and circadian rhythm alignment.",
            status: "ready",
            progress: 35,
            errorMessage: nil,
            gdriveFolderId: nil
        ),
        Episode(
            id: "ep_lex_sam",
            feedId: "feed_lex",
            guid: "lex_002",
            title: "Sam Altman: OpenAI, GPT-5, and the Future of AGI",
            audioUrl: "https://traffic.libsyn.com/secure/lexfridman/lex_ai_sam_altman.mp3",
            duration: 7320,
            pubDate: "2026-10-10",
            shownotes: "Sam Altman on frontier AI alignment, synthetic intelligence architecture, and next-generation compute clusters.",
            status: "ready",
            progress: 80,
            errorMessage: nil,
            gdriveFolderId: nil
        )
    ]
}
// MARK: - Episode
public struct Episode: Identifiable, Codable, Hashable {
    public let id: String
    public let feedId: String
    public let guid: String
    public let title: String
    public let audioUrl: String
    public let duration: Int
    public let pubDate: String
    public let shownotes: String
    public var status: String           // "idle", "transcribing", "translating", "synthesizing", "ready", "failed"
    public var progress: Int
    public var errorMessage: String?
    public var gdriveFolderId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case feedId = "feed_id"
        case guid, title
        case audioUrl = "audio_url"
        case duration
        case pubDate = "pub_date"
        case shownotes, status, progress
        case errorMessage = "error_message"
        case gdriveFolderId = "gdrive_folder_id"
    }

    public init(
        id: String,
        feedId: String,
        guid: String,
        title: String,
        audioUrl: String,
        duration: Int,
        pubDate: String,
        shownotes: String,
        status: String = "ready",
        progress: Int = 0,
        errorMessage: String? = nil,
        gdriveFolderId: String? = nil
    ) {
        self.id = id
        self.feedId = feedId
        self.guid = guid
        self.title = title
        self.audioUrl = audioUrl
        self.duration = duration
        self.pubDate = pubDate
        self.shownotes = shownotes
        self.status = status
        self.progress = progress
        self.errorMessage = errorMessage
        self.gdriveFolderId = gdriveFolderId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.feedId = try container.decodeIfPresent(String.self, forKey: .feedId) ?? ""
        self.guid = try container.decodeIfPresent(String.self, forKey: .guid) ?? id
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "未知单集"
        self.audioUrl = try container.decodeIfPresent(String.self, forKey: .audioUrl) ?? ""
        self.duration = try container.decodeIfPresent(Int.self, forKey: .duration) ?? 0
        self.pubDate = try container.decodeIfPresent(String.self, forKey: .pubDate) ?? ""
        self.shownotes = try container.decodeIfPresent(String.self, forKey: .shownotes) ?? ""
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "ready"
        self.progress = try container.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        self.errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        self.gdriveFolderId = try container.decodeIfPresent(String.self, forKey: .gdriveFolderId)
    }

    public var isReady: Bool {
        status == "ready"
    }

    public var isProcessing: Bool {
        ["transcribing", "translating", "synthesizing", "pending"].contains(status)
    }

    public var formattedDuration: String {
        let sec = max(0, duration)
        let m = sec / 60
        let s = sec % 60
        let h = m / 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m % 60, s)
        } else {
            return String(format: "%02d:%02d", m, s)
        }
    }
}

// MARK: - Timing Sync (tens of KB, resident in player)
public struct TimingRange: Codable, Hashable {
    public let start: Double
    public let end: Double
}

public struct TimingSegment: Identifiable, Codable, Hashable {
    public let id: Int
    public let speaker: String
    public let en: TimingRange
    public let zh: TimingRange
}

// MARK: - Full Mapping Subtitles (Word-by-word synced)
public struct WordTimestamp: Codable, Hashable {
    public let word: String
    public let start: Double
    public let end: Double
}

public struct FullMappingSegment: Identifiable, Codable, Hashable {
    public var id: Int { index }
    public let index: Int
    public let speaker: String
    public let enText: String
    public let zhDisplay: String
    public let zhSpoken: String
    public let enRange: TimingRange
    public let zhRange: TimingRange
    public let enWords: [WordTimestamp]?
    public let zhWords: [WordTimestamp]?

    enum CodingKeys: String, CodingKey {
        case index, speaker
        case enText = "en_text"
        case zhDisplay = "zh_display"
        case zhSpoken = "zh_spoken"
        case enRange = "en_range"
        case zhRange = "zh_range"
        case enWords = "en_words"
        case zhWords = "zh_words"
    }
}

// MARK: - Chapter
public struct Chapter: Identifiable, Codable, Hashable {
    public var id: String { "\(title)_\(startSec)" }
    public let title: String
    public let startSec: Double

    enum CodingKeys: String, CodingKey {
        case title
        case startSec = "start_sec"
    }
}

// MARK: - Episode Artifacts Response
public struct EpisodeArtifacts: Codable {
    public let episodeId: String
    public let status: String
    public let timingSync: [TimingSegment]
    public let fullMapping: [FullMappingSegment]
    public let chapters: [Chapter]
    public let articleMarkdown: String
    public let streaming: StreamingInfo

    enum CodingKeys: String, CodingKey {
        case episodeId = "episode_id"
        case status
        case timingSync = "timing_sync"
        case fullMapping = "full_mapping"
        case chapters
        case articleMarkdown = "article_markdown"
        case streaming
    }
}

public struct StreamingInfo: Codable {
    public let episodeId: String
    public let isArchivedInGdrive: Bool
    public let googleAccessToken: String?
    public let streamEndpoint: String

    enum CodingKeys: String, CodingKey {
        case episodeId = "episode_id"
        case isArchivedInGdrive = "is_archived_in_gdrive"
        case googleAccessToken = "google_access_token"
        case streamEndpoint = "stream_endpoint"
    }
}

// MARK: - Playback Progress
public struct PlaybackProgress: Codable {
    public let episodeId: String
    public let positionMs: Int
    public let durationMs: Int
    public let trackMode: String
    public let isFinished: Int?

    enum CodingKeys: String, CodingKey {
        case episodeId = "episode_id"
        case positionMs = "position_ms"
        case durationMs = "duration_ms"
        case trackMode = "track_mode"
        case isFinished = "is_finished"
    }
}

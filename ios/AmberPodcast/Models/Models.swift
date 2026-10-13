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

    enum CodingKeys: String, CodingKey {
        case id
        case sourceType = "source_type"
        case title, author
        case feedUrl = "feed_url"
        case coverUrl = "cover_url"
        case description
        case autoTranslate = "auto_translate"
    }
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

    public var isReady: Bool {
        status == "ready"
    }

    public var isProcessing: Bool {
        ["transcribing", "translating", "synthesizing", "pending"].contains(status)
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

# Amber Podcast - Domain Model & Glossary

## 1. Domain Entities

- **PodcastFeed**: A podcast subscription source.
  - `id`: Unique identifier (string, e.g. `feed_apple_12345` or `feed_xyz_682c566c`).
  - `source_type`: `"apple_rss"` (standard RSS) or `"xiaoyuzhou"` (Xiaoyuzhou FM).
  - `title`: Show name.
  - `author`: Host or network.
  - `feed_url`: RSS link or Xiaoyuzhou podcast link.
  - `cover_url`: Artwork image URL.
  - `description`: Show summary.
  - `auto_translate`: Boolean flag indicating whether new episodes should be automatically processed in the background.

- **Episode**: A single episode within a PodcastFeed.
  - `id`: Episode unique ID.
  - `feed_id`: Reference to PodcastFeed.
  - `title`: Episode title.
  - `audio_url`: Original audio enclosure URL (`.mp3` / `.m4a`).
  - `duration`: Duration in seconds.
  - `pub_date`: Publication date.
  - `shownotes`: HTML or plaintext shownotes (timestamps like `12:34` parsed as jump links).
  - `status`: `"idle"` | `"pending"` | `"transcribing"` | `"translating"` | `"synthesizing"` | `"ready"` | `"failed"`.
  - `progress`: Integer percentage `0..100`.
  - `error_message`: Error details if failed.

- **TimingSegment (`timing_sync.json`)**:
  - Lightweight dual-track timing synchronization array (tens of KB, permanently resident in iOS player).
  - `{ id: int, speaker: string, en: { start: float, end: float }, zh: { start: float, end: float } }` (units: seconds).
  - Allows instant EN ↔ ZH audio track switching and bilingual alternating sentence playback.

- **FullMappingSegment (`full_mapping.json`)**:
  - Full bilingual subtitle and word-level alignment table loaded on-demand by the UI.
  - `{ index: int, speaker: string, en_text: string, zh_display: string, zh_spoken: string, en_range: { start, end }, zh_range: { start, end }, en_words: [{ word, start, end }], zh_words: [{ word, start, end }] }`.

- **Chapter (`chapters.json`)**:
  - `{ title: string, start_sec: float }`.

- **EpisodeArticle (`article.md`)**:
  - Deep Markdown summary & structured reading notes extracted from the episode.

- **PlaybackProgress**:
  - `{ episode_id, position_ms, track_mode: "original" | "chinese" | "alternating", updated_at }`.

## 2. Storage Tiers

- **Tier 1 (Local NVMe SSD)**:
  - `/root/projects/amber-podcast/data/amber.db` (SQLite WAL mode).
- **Tier 2 (Local Scratch Buffer)**:
  - `/root/.hermes/cache/scratch/amber/` (temporary TTS chunks and FFmpeg concatenation workspace).
- **Tier 3 (Google Drive 5TB Permanent Archive)**:
  - `/mnt/gdrive/podcasts/episodes/<episode_id>/`
  - Contains: `chinese.m4a`, `original.m4a`, `timing_sync.json`, `full_mapping.json`, `chapters.json`, `article.md`.
  - Served directly to mobile clients via Google Drive API v3 edge URLs.

import sqlite3
import json
import time
from email.utils import parsedate_to_datetime
from typing import Optional, List, Dict, Any
from pathlib import Path
from amber_podcast.config import DB_PATH


def _pub_ts(pub_date: Optional[str]) -> int:
    """Parse an RFC 822 podcast pub_date into an epoch timestamp (0 if unknown).

    ``episodes.pub_date`` is stored as TEXT, so ``ORDER BY pub_date`` compares
    strings ("Wed, 31 May 2023" > "Wed, 11 Nov 2026"). Every write must also
    persist ``pub_ts`` so recency queries can sort numerically.
    """
    if not pub_date:
        return 0
    try:
        return int(parsedate_to_datetime(pub_date).timestamp())
    except (TypeError, ValueError, OverflowError):
        return 0

SCHEMA = """
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS feeds (
    id TEXT PRIMARY KEY,
    source_type TEXT NOT NULL,          -- 'apple_rss', 'xiaoyuzhou'
    title TEXT NOT NULL,
    author TEXT DEFAULT '',
    feed_url TEXT NOT NULL UNIQUE,
    cover_url TEXT DEFAULT '',
    description TEXT DEFAULT '',
    auto_translate INTEGER DEFAULT 0,  -- 0 or 1
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS episodes (
    id TEXT PRIMARY KEY,
    feed_id TEXT NOT NULL,
    guid TEXT DEFAULT '',
    title TEXT NOT NULL,
    audio_url TEXT NOT NULL,
    duration INTEGER DEFAULT 0,         -- in seconds
    pub_date TEXT DEFAULT '',
    pub_ts INTEGER DEFAULT 0,           -- pub_date parsed to epoch; TEXT sorting is lexicographic and wrong
    shownotes TEXT DEFAULT '',
    status TEXT DEFAULT 'idle',         -- 'idle', 'transcribing', 'translating', 'synthesizing', 'ready', 'failed'
    progress INTEGER DEFAULT 0,         -- 0 to 100
    error_message TEXT DEFAULT '',
    gdrive_folder_id TEXT DEFAULT '',
    dump_started_at INTEGER DEFAULT 0,   -- epoch seconds when the dump pipeline started
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(feed_id) REFERENCES feeds(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_episodes_feed_id ON episodes(feed_id);
CREATE INDEX IF NOT EXISTS idx_episodes_status ON episodes(status);

CREATE TABLE IF NOT EXISTS playback_progress (
    episode_id TEXT PRIMARY KEY,
    position_ms INTEGER NOT NULL DEFAULT 0,
    duration_ms INTEGER NOT NULL DEFAULT 0,
    track_mode TEXT NOT NULL DEFAULT 'chinese', -- 'original', 'chinese', 'alternating'
    is_finished INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(episode_id) REFERENCES episodes(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS settings (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at INTEGER NOT NULL
);
"""

class Database:
    def __init__(self, db_path: Optional[str] = None):
        self.db_path = db_path or DB_PATH
        Path(self.db_path).parent.mkdir(parents=True, exist_ok=True)
        self.init_db()

    def get_conn(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA foreign_keys = ON;")
        return conn

    def init_db(self):
        with self.get_conn() as conn:
            conn.executescript(SCHEMA)
            # Lightweight migrations for pre-existing databases
            cols = {row[1] for row in conn.execute("PRAGMA table_info(episodes)").fetchall()}
            if "dump_started_at" not in cols:
                conn.execute("ALTER TABLE episodes ADD COLUMN dump_started_at INTEGER DEFAULT 0")
            if "pub_ts" not in cols:
                conn.execute("ALTER TABLE episodes ADD COLUMN pub_ts INTEGER DEFAULT 0")
                # backfill: pub_date is TEXT, so every existing row needs a parsed epoch
                for eid, pub_date in conn.execute(
                    "SELECT id, pub_date FROM episodes WHERE pub_date != ''"
                ).fetchall():
                    conn.execute(
                        "UPDATE episodes SET pub_ts = ? WHERE id = ?",
                        (_pub_ts(pub_date), eid),
                    )
            conn.execute("CREATE INDEX IF NOT EXISTS idx_episodes_pub_ts ON episodes(pub_ts DESC)")

    # --- Feed operations ---
    def upsert_feed(self, feed_id: str, source_type: str, title: str, author: str,
                    feed_url: str, cover_url: str, description: str, auto_translate: int = 0) -> Optional[Dict[str, Any]]:
        now = int(time.time())
        with self.get_conn() as conn:
            conn.execute("""
                INSERT INTO feeds (id, source_type, title, author, feed_url, cover_url, description, auto_translate, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(feed_url) DO UPDATE SET
                    title=excluded.title,
                    author=excluded.author,
                    cover_url=excluded.cover_url,
                    description=excluded.description,
                    auto_translate=excluded.auto_translate,
                    updated_at=excluded.updated_at
            """, (feed_id, source_type, title, author, feed_url, cover_url, description, auto_translate, now, now))
        # feed_url 是唯一标识，返回按 URL 查到的实际 feed（可能是历史旧 id）
        return self.get_feed_by_url(feed_url)

    def get_feed(self, feed_id: str) -> Optional[Dict[str, Any]]:
        with self.get_conn() as conn:
            row = conn.execute("SELECT * FROM feeds WHERE id = ?", (feed_id,)).fetchone()
            return dict(row) if row else None

    def get_feed_by_url(self, feed_url: str) -> Optional[Dict[str, Any]]:
        with self.get_conn() as conn:
            row = conn.execute("SELECT * FROM feeds WHERE feed_url = ?", (feed_url,)).fetchone()
            return dict(row) if row else None

    def list_feeds(self) -> List[Dict[str, Any]]:
        with self.get_conn() as conn:
            rows = conn.execute("SELECT * FROM feeds ORDER BY updated_at DESC").fetchall()
            return [dict(r) for r in rows]

    def delete_feed(self, feed_id: str) -> bool:
        with self.get_conn() as conn:
            cur = conn.execute("DELETE FROM feeds WHERE id = ?", (feed_id,))
            return cur.rowcount > 0

    # --- Episode operations ---
    def upsert_episode(self, episode_id: str, feed_id: str, title: str, audio_url: str,
                       duration: int = 0, pub_date: str = "", shownotes: str = "", guid: str = "") -> Optional[Dict[str, Any]]:
        now = int(time.time())
        with self.get_conn() as conn:
            conn.execute("""
                INSERT INTO episodes (id, feed_id, guid, title, audio_url, duration, pub_date, pub_ts, shownotes, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title=excluded.title,
                    audio_url=excluded.audio_url,
                    duration=excluded.duration,
                    pub_date=excluded.pub_date,
                    pub_ts=excluded.pub_ts,
                    shownotes=excluded.shownotes,
                    updated_at=excluded.updated_at
            """, (episode_id, feed_id, guid, title, audio_url, duration, pub_date, _pub_ts(pub_date), shownotes, now, now))
        return self.get_episode(episode_id)

    def get_episode(self, episode_id: str) -> Optional[Dict[str, Any]]:
        with self.get_conn() as conn:
            row = conn.execute("SELECT * FROM episodes WHERE id = ?", (episode_id,)).fetchone()
            return dict(row) if row else None

    def get_episode_by_guid(self, feed_id: str, guid: str) -> Optional[Dict[str, Any]]:
        """Look an episode up by its RSS guid.

        Episode ids were not always derived the same way (older rows used a
        different hash), so a feed poll that recomputes ``{feed_id}_{hash(guid)}``
        can disagree with the id already stored. Reusing the stored id by guid
        is the only safe way to avoid duplicating the entire back-catalogue on
        every poll.
        """
        if not guid:
            return None
        with self.get_conn() as conn:
            # Deliberately NOT SELECT *: a single row with non-UTF8 bytes in a
            # large text column (shownotes) makes sqlite3 raise on decode, and
            # this lookup runs inside the feed poll. Only the identity columns
            # are needed to decide whether the guide already exists.
            row = conn.execute(
                "SELECT id, feed_id, guid FROM episodes WHERE feed_id = ? AND guid = ? ORDER BY created_at LIMIT 1",
                (feed_id, guid),
            ).fetchone()
            return dict(row) if row else None

    def list_episodes(self, feed_id: Optional[str] = None, limit: int = 50, offset: int = 0) -> List[Dict[str, Any]]:
        with self.get_conn() as conn:
            if feed_id:
                rows = conn.execute(
                    "SELECT * FROM episodes WHERE feed_id = ? ORDER BY pub_ts DESC, created_at DESC LIMIT ? OFFSET ?",
                    (feed_id, limit, offset)
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM episodes ORDER BY pub_ts DESC, created_at DESC LIMIT ? OFFSET ?",
                    (limit, offset)
                ).fetchall()
            return [dict(r) for r in rows]

    def list_episodes_by_statuses(self, statuses: List[str], limit: int = 500) -> List[Dict[str, Any]]:
        """Query episodes directly by status.

        `list_episodes` orders by pub_date and is paginated, so a stale failed
        task can fall outside the window and silently vanish from the queue.
        Status queries must never depend on that ordering.
        """
        if not statuses:
            return []
        placeholders = ",".join("?" for _ in statuses)
        with self.get_conn() as conn:
            rows = conn.execute(
                f"SELECT * FROM episodes WHERE status IN ({placeholders}) "
                "ORDER BY updated_at DESC LIMIT ?",
                (*statuses, limit),
            ).fetchall()
            return [dict(r) for r in rows]

    def update_episode_status(self, episode_id: str, status: str, progress: int = 0,
                              error_message: str = "", gdrive_folder_id: str = "") -> None:
        now = int(time.time())
        with self.get_conn() as conn:
            conn.execute("""
                UPDATE episodes
                SET status = ?, progress = ?, error_message = ?, gdrive_folder_id = CASE WHEN ? != '' THEN ? ELSE gdrive_folder_id END, updated_at = ?
                WHERE id = ?
            """, (status, progress, error_message, gdrive_folder_id, gdrive_folder_id, now, episode_id))

    def mark_dump_started(self, episode_id: str) -> None:
        """Stamp the moment the dump pipeline actually began for this episode."""
        now = int(time.time())
        with self.get_conn() as conn:
            conn.execute(
                "UPDATE episodes SET dump_started_at = ? WHERE id = ?",
                (now, episode_id),
            )

    # --- Playback progress ---
    def update_playback_progress(self, episode_id: str, position_ms: int, duration_ms: int,
                                 track_mode: str = "chinese", is_finished: int = 0) -> None:
        now = int(time.time())
        # Safeguard: if episode is not yet persisted in database (e.g. preview mode), skip foreign key failure
        if not self.get_episode(episode_id):
            return

        with self.get_conn() as conn:
            conn.execute("""
                INSERT INTO playback_progress (episode_id, position_ms, duration_ms, track_mode, is_finished, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(episode_id) DO UPDATE SET
                    position_ms = excluded.position_ms,
                    duration_ms = excluded.duration_ms,
                    track_mode = excluded.track_mode,
                    is_finished = excluded.is_finished,
                    updated_at = excluded.updated_at
            """, (episode_id, position_ms, duration_ms, track_mode, is_finished, now))

    def get_playback_progress(self, episode_id: str) -> Optional[Dict[str, Any]]:
        with self.get_conn() as conn:
            row = conn.execute("SELECT * FROM playback_progress WHERE episode_id = ?", (episode_id,)).fetchone()
            return dict(row) if row else None

    # --- Settings (key/value, user-tunable pipeline behaviour) ---
    def get_settings(self) -> Dict[str, str]:
        with self.get_conn() as conn:
            return {row["key"]: row["value"]
                    for row in conn.execute("SELECT key, value FROM settings")}

    def set_settings(self, updates: Dict[str, Any]) -> Dict[str, str]:
        now = int(time.time())
        with self.get_conn() as conn:
            for key, value in updates.items():
                conn.execute(
                    "INSERT INTO settings (key, value, updated_at) VALUES (?, ?, ?) "
                    "ON CONFLICT(key) DO UPDATE SET value=excluded.value, updated_at=excluded.updated_at",
                    (key, str(value), now),
                )
        return self.get_settings()

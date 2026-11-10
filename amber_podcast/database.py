import sqlite3
import json
import time
from typing import Optional, List, Dict, Any
from pathlib import Path
from amber_podcast.config import DB_PATH

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
    shownotes TEXT DEFAULT '',
    status TEXT DEFAULT 'idle',         -- 'idle', 'transcribing', 'translating', 'synthesizing', 'ready', 'failed'
    progress INTEGER DEFAULT 0,         -- 0 to 100
    error_message TEXT DEFAULT '',
    gdrive_folder_id TEXT DEFAULT '',
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

    # --- Feed operations ---
    def upsert_feed(self, feed_id: str, source_type: str, title: str, author: str,
                    feed_url: str, cover_url: str, description: str, auto_translate: int = 0) -> Optional[Dict[str, Any]]:
        now = int(time.time())
        with self.get_conn() as conn:
            existing = conn.execute("SELECT id FROM feeds WHERE feed_url = ?", (feed_url,)).fetchone()
            if existing and existing["id"] != feed_id:
                actual_id = existing["id"]
                conn.execute("""
                    UPDATE feeds SET
                        title = ?,
                        author = ?,
                        cover_url = ?,
                        description = ?,
                        auto_translate = ?,
                        updated_at = ?
                    WHERE id = ?
                """, (title, author, cover_url, description, auto_translate, now, actual_id))
                return self.get_feed(actual_id)

            conn.execute("""
                INSERT INTO feeds (id, source_type, title, author, feed_url, cover_url, description, auto_translate, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title=excluded.title,
                    author=excluded.author,
                    cover_url=excluded.cover_url,
                    description=excluded.description,
                    auto_translate=excluded.auto_translate,
                    updated_at=excluded.updated_at
            """, (feed_id, source_type, title, author, feed_url, cover_url, description, auto_translate, now, now))
        return self.get_feed(feed_id)

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
                INSERT INTO episodes (id, feed_id, guid, title, audio_url, duration, pub_date, shownotes, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title=excluded.title,
                    audio_url=excluded.audio_url,
                    duration=excluded.duration,
                    pub_date=excluded.pub_date,
                    shownotes=excluded.shownotes,
                    updated_at=excluded.updated_at
            """, (episode_id, feed_id, guid, title, audio_url, duration, pub_date, shownotes, now, now))
        return self.get_episode(episode_id)

    def get_episode(self, episode_id: str) -> Optional[Dict[str, Any]]:
        with self.get_conn() as conn:
            row = conn.execute("SELECT * FROM episodes WHERE id = ?", (episode_id,)).fetchone()
            return dict(row) if row else None

    def list_episodes(self, feed_id: Optional[str] = None, limit: int = 50, offset: int = 0) -> List[Dict[str, Any]]:
        with self.get_conn() as conn:
            if feed_id:
                rows = conn.execute(
                    "SELECT * FROM episodes WHERE feed_id = ? ORDER BY pub_date DESC, created_at DESC LIMIT ? OFFSET ?",
                    (feed_id, limit, offset)
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM episodes ORDER BY pub_date DESC, created_at DESC LIMIT ? OFFSET ?",
                    (limit, offset)
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

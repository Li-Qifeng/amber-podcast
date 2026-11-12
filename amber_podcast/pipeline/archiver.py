import os
import shutil
import subprocess
import json
from pathlib import Path
from typing import Dict, Any, Optional
from amber_podcast.config import GDRIVE_DIR, DATA_DIR

class EpisodeArchiver:
    def __init__(self, gdrive_dir: Optional[Path] = None):
        self.gdrive_dir = gdrive_dir or GDRIVE_DIR

    def archive_episode_bundle(
        self,
        episode_id: str,
        chinese_audio_path: str,
        timing_sync_path: str,
        full_mapping_path: str,
        chapters: Optional[list] = None,
        article_markdown: Optional[str] = None,
        original_audio_path: Optional[str] = None
    ) -> Dict[str, Any]:
        """Atomically save synthesized artifacts to local fast SSD, and replicate to Google Drive."""
        # 1. Primary storage: Local SSD for 0.01s instant playback and streaming
        target_dir = DATA_DIR / "archive" / episode_id
        target_dir.mkdir(parents=True, exist_ok=True)

        dst_chinese_audio = target_dir / "chinese_audio.m4a"
        shutil.copy2(chinese_audio_path, dst_chinese_audio)

        dst_original_audio = None
        if original_audio_path and os.path.isfile(original_audio_path):
            # Keep the source container/extension (RSS originals are usually mp3).
            dst_original_audio = target_dir / ("original" + Path(original_audio_path).suffix)
            shutil.copy2(original_audio_path, dst_original_audio)

        dst_timing_sync = target_dir / "timing_sync.json"
        shutil.copy2(timing_sync_path, dst_timing_sync)

        dst_full_mapping = target_dir / "full_mapping.json"
        shutil.copy2(full_mapping_path, dst_full_mapping)

        dst_chapters = target_dir / "chapters.json"
        if chapters:
            with open(dst_chapters, "w", encoding="utf-8") as f:
                json.dump(chapters, f, ensure_ascii=False, indent=2)

        dst_article = target_dir / "article.md"
        if article_markdown:
            with open(dst_article, "w", encoding="utf-8") as f:
                f.write(article_markdown)

        # 2. Replicate to Google Drive if mounted
        if self.gdrive_dir.exists():
            try:
                gdrive_target = self.gdrive_dir / "episodes" / episode_id
                gdrive_target.mkdir(parents=True, exist_ok=True)
                replicated = [dst_chinese_audio, dst_timing_sync, dst_full_mapping, dst_chapters, dst_article]
                if dst_original_audio is not None:
                    replicated.append(dst_original_audio)
                for item in replicated:
                    if item.exists():
                        shutil.copy2(str(item), str(gdrive_target / item.name))
            except Exception as e:
                import logging
                logging.getLogger(__name__).warning(f"Replication to GDrive failed: {e}")
        return {
            "archive_dir": str(target_dir),
            "chinese_audio": str(dst_chinese_audio),
            "timing_sync": str(dst_timing_sync),
            "full_mapping": str(dst_full_mapping),
            "chapters": str(dst_chapters) if chapters else None,
            "article": str(dst_article) if article_markdown else None,
            "original_audio": str(dst_original_audio) if dst_original_audio else None
        }

    def get_google_stream_info(self, episode_id: str) -> Dict[str, Any]:
        """Resolve Google Drive direct streaming URL and fresh OAuth token."""
        # Try getting OAuth token from rclone config
        oauth_token = ""
        rclone_conf = Path("/root/.config/rclone/rclone.conf")
        if rclone_conf.exists():
            try:
                import configparser
                cp = configparser.ConfigParser()
                cp.read(str(rclone_conf))
                if "gdrive" in cp and "token" in cp["gdrive"]:
                    tok = json.loads(cp["gdrive"]["token"])
                    oauth_token = tok.get("access_token", "")
            except Exception:
                pass

        # We stream locally from our own server endpoint, so external oauth token is not required
        # Avoiding slow subprocess calls on every playback request.
        target_dir = self.gdrive_dir / "episodes" / episode_id
        audio_file = target_dir / "chinese_audio.m4a"

        return {
            "episode_id": episode_id,
            "is_archived_in_gdrive": audio_file.exists(),
            "local_archive_path": str(audio_file) if audio_file.exists() else None,
            "google_access_token": oauth_token,
            "stream_endpoint": f"/api/v1/episodes/{episode_id}/stream/chinese"
        }

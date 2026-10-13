import httpx
import json
import re
from typing import Dict, Any, Optional, List

class XiaoyuzhouAggregator:
    def __init__(self, timeout: float = 15.0):
        self.timeout = timeout
        self.headers = {
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        }

    def parse_next_data(self, html: str) -> Optional[Dict[str, Any]]:
        """Extract __NEXT_DATA__ JSON blob from Xiaoyuzhou web pages."""
        match = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', html, re.DOTALL)
        if match:
            try:
                return json.loads(match.group(1))
            except json.JSONDecodeError:
                return None
        return None

    def parse_episode_page(self, html: str, feed_id: Optional[str] = None) -> Dict[str, Any]:
        """Parse a Xiaoyuzhou episode page and return structured episode details."""
        data = self.parse_next_data(html)
        if not data:
            raise ValueError("Could not find __NEXT_DATA__ in Xiaoyuzhou episode page")

        page_props = data.get("props", {}).get("pageProps", {})
        ep = page_props.get("episode", {})
        podcast = ep.get("podcast", {})

        eid = ep.get("eid", "")
        pid = podcast.get("pid", "")
        actual_feed_id = feed_id or f"xyz_{pid}"

        # Resolve media URL
        media = ep.get("media", {})
        audio_url = ""
        if isinstance(media, dict):
            source = media.get("source", {})
            if isinstance(source, dict):
                audio_url = source.get("url", "")
        if not audio_url:
            enclosure = ep.get("enclosure", {})
            if isinstance(enclosure, dict):
                audio_url = enclosure.get("url", "")

        duration = ep.get("duration", 0)
        title = ep.get("title", "")
        shownotes = ep.get("shownotes") or ep.get("description") or ""
        pub_date = ep.get("pubDate", "")

        return {
            "feed": {
                "id": actual_feed_id,
                "source_type": "xiaoyuzhou",
                "title": podcast.get("title", ""),
                "author": podcast.get("author", ""),
                "cover_url": (podcast.get("image", {}) or {}).get("largePicUrl", "") if isinstance(podcast.get("image"), dict) else "",
                "description": podcast.get("description", "")
            },
            "episode": {
                "id": f"xyz_ep_{eid}",
                "feed_id": actual_feed_id,
                "guid": eid,
                "title": title,
                "audio_url": audio_url,
                "duration": duration,
                "pub_date": pub_date,
                "shownotes": shownotes
            }
        }

    async def fetch_episode(self, episode_url_or_id: str, feed_id: Optional[str] = None) -> Dict[str, Any]:
        """Fetch Xiaoyuzhou episode by URL or eid."""
        if episode_url_or_id.startswith("http"):
            url = episode_url_or_id
        else:
            url = f"https://www.xiaoyuzhoufm.com/episode/{episode_url_or_id}"

        async with httpx.AsyncClient(timeout=self.timeout, follow_redirects=True) as client:
            resp = await client.get(url, headers=self.headers)
            resp.raise_for_status()
            return self.parse_episode_page(resp.text, feed_id)

    async def fetch_podcast_episodes(self, pid_or_url: str) -> Dict[str, Any]:
        """Fetch Xiaoyuzhou podcast page and return feed info + initial episodes."""
        if pid_or_url.startswith("http"):
            url = pid_or_url
        else:
            url = f"https://www.xiaoyuzhoufm.com/podcast/{pid_or_url}"

        async with httpx.AsyncClient(timeout=self.timeout, follow_redirects=True) as client:
            resp = await client.get(url, headers=self.headers)
            resp.raise_for_status()
            html = resp.text

        data = self.parse_next_data(html)
        if not data:
            raise ValueError("Could not find __NEXT_DATA__ in Xiaoyuzhou podcast page")

        page_props = data.get("props", {}).get("pageProps", {})
        podcast = page_props.get("podcast", {})
        pid = podcast.get("pid", "")
        feed_id = f"xyz_{pid}"

        feed_info = {
            "id": feed_id,
            "source_type": "xiaoyuzhou",
            "title": podcast.get("title", ""),
            "author": podcast.get("author", ""),
            "cover_url": (podcast.get("image", {}) or {}).get("largePicUrl", "") if isinstance(podcast.get("image"), dict) else "",
            "description": podcast.get("description", "")
        }

        episodes = []
        for ep in page_props.get("episodes", []):
            eid = ep.get("eid", "")
            media = ep.get("media", {})
            audio_url = ""
            if isinstance(media, dict):
                source = media.get("source", {})
                if isinstance(source, dict):
                    audio_url = source.get("url", "")
            if not audio_url:
                enclosure = ep.get("enclosure", {})
                if isinstance(enclosure, dict):
                    audio_url = enclosure.get("url", "")

            if audio_url:
                episodes.append({
                    "id": f"xyz_ep_{eid}",
                    "feed_id": feed_id,
                    "guid": eid,
                    "title": ep.get("title", ""),
                    "audio_url": audio_url,
                    "duration": ep.get("duration", 0),
                    "pub_date": ep.get("pubDate", ""),
                    "shownotes": ep.get("shownotes") or ep.get("description") or ""
                })

        return {
            "feed": feed_info,
            "episodes": episodes
        }

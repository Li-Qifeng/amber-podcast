import httpx
import xml.etree.ElementTree as ET
import re
import asyncio
import time
from typing import List, Dict, Any, Optional
from urllib.parse import quote

class ApplePodcastAggregator:
    def __init__(self, timeout: float = 15.0):
        self.timeout = timeout
        self._top_cache: Dict[str, Dict[str, Any]] = {}  # {country: {"time": ts, "data": [...]}}
        self._cache_ttl = 3600 * 6  # 6 hours

    async def lookup_podcasts_batch(self, ids: List[str]) -> List[Dict[str, Any]]:
        """Batch lookup podcast metadata from iTunes API."""
        if not ids:
            return []
        ids_str = ",".join(ids[:50])
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            try:
                resp = await client.get(f"https://itunes.apple.com/lookup?id={ids_str}")
                if resp.status_code != 200:
                    return []
                results = []
                for item in resp.json().get("results", []):
                    cid = str(item.get("collectionId", ""))
                    feed_url = item.get("feedUrl", "")
                    if not cid or not feed_url:
                        continue
                    genre = item.get("primaryGenreName", "")
                    track_count = item.get("trackCount", 0)
                    desc = f"{genre} · {track_count} 集" if track_count else genre
                    results.append({
                        "id": cid,
                        "collection_id": cid,
                        "source_type": "apple_rss",
                        "title": item.get("collectionName", ""),
                        "author": item.get("artistName", ""),
                        "feed_url": feed_url,
                        "cover_url": item.get("artworkUrl600", item.get("artworkUrl100", "")),
                        "description": desc,
                        "genre": genre,
                        "track_count": track_count,
                        "auto_translate": 0
                    })
                return results
            except Exception:
                return []

    async def fetch_top_podcasts(self, country: str = "cn", limit: int = 25) -> List[Dict[str, Any]]:
        """Fetch real-time top podcasts from Apple Podcasts RSS and resolve metadata."""
        now = time.time()
        if country in self._top_cache:
            entry = self._top_cache[country]
            if now - entry["time"] < self._cache_ttl and entry["data"]:
                return entry["data"][:limit]

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                resp = await client.get(f"https://itunes.apple.com/{country}/rss/toppodcasts/limit={limit}/json")
                if resp.status_code == 200:
                    data = resp.json()
                    entries = data.get("feed", {}).get("entry", [])
                    ids = [
                        e["id"]["attributes"]["im:id"]
                        for e in entries
                        if "id" in e and "attributes" in e["id"] and "im:id" in e["id"]["attributes"]
                    ]
                    podcasts = await self.lookup_podcasts_batch(ids)
                    if podcasts:
                        self._top_cache[country] = {"time": now, "data": podcasts}
                        return podcasts[:limit]
        except Exception:
            pass

        # Return cached even if expired
        if country in self._top_cache and self._top_cache[country]["data"]:
            return self._top_cache[country]["data"][:limit]
        return []

    async def search_podcasts(self, query: str, limit: int = 15, country: Optional[str] = None) -> List[Dict[str, Any]]:
        """Search Apple Podcasts Directory API for shows, with multi-region support (CN + US)."""
        clean_q = query.strip()
        if not clean_q:
            return []
        
        has_cjk = bool(re.search(r"[\u4e00-\u9fa5]", clean_q))
        regions = [country] if country else (["cn", "us"] if has_cjk else ["us", "cn"])

        async with httpx.AsyncClient(timeout=self.timeout) as client:
            tasks = [
                client.get(f"https://itunes.apple.com/search?term={quote(clean_q)}&entity=podcast&country={r}&limit={limit}")
                for r in regions
            ]
            responses = await asyncio.gather(*tasks, return_exceptions=True)

        results = []
        seen_ids = set()
        for resp in responses:
            if not isinstance(resp, httpx.Response) or resp.status_code != 200:
                continue
            data = resp.json()
            for item in data.get("results", []):
                cid = str(item.get("collectionId", ""))
                feed_url = item.get("feedUrl", "")
                if not cid or not feed_url or cid in seen_ids:
                    continue
                seen_ids.add(cid)
                genre = item.get("primaryGenreName", "")
                track_count = item.get("trackCount", 0)
                desc = f"{genre} · {track_count} 集" if track_count else genre
                results.append({
                    "id": cid,
                    "collection_id": cid,
                    "source_type": "apple_rss",
                    "title": item.get("collectionName", ""),
                    "author": item.get("artistName", ""),
                    "feed_url": feed_url,
                    "cover_url": item.get("artworkUrl600", item.get("artworkUrl100", "")),
                    "description": desc,
                    "genre": genre,
                    "track_count": track_count,
                    "auto_translate": 0
                })
                if len(results) >= limit:
                    break
            if len(results) >= limit:
                break
        return results

    def parse_rss_xml(self, xml_content: str, feed_id: str) -> Dict[str, Any]:
        """Parse podcast RSS XML and return feed metadata and episodes."""
        root = ET.fromstring(xml_content)
        channel = root.find("channel")
        if channel is None:
            raise ValueError("Invalid RSS: missing <channel>")

        # Channel metadata
        title = (channel.findtext("title") or "").strip()
        description = (channel.findtext("description") or "").strip()
        author = (channel.findtext("{http://www.itunes.com/dtds/podcast-1.0.dtd}author") or "").strip()
        
        # Cover image
        cover_url = ""
        itunes_image = channel.find("{http://www.itunes.com/dtds/podcast-1.0.dtd}image")
        if itunes_image is not None and "href" in itunes_image.attrib:
            cover_url = itunes_image.attrib["href"]
        elif channel.find("image/url") is not None:
            cover_url = channel.findtext("image/url") or ""

        episodes = []
        for item in channel.findall("item"):
            ep_title = (item.findtext("title") or "").strip()
            guid = (item.findtext("guid") or "").strip()
            pub_date = (item.findtext("pubDate") or "").strip()
            shownotes = (item.findtext("{http://purl.org/rss/1.0/modules/content/}encoded") or 
                         item.findtext("description") or "").strip()

            # Enclosure audio URL
            audio_url = ""
            enclosure = item.find("enclosure")
            if enclosure is not None and "url" in enclosure.attrib:
                audio_url = enclosure.attrib["url"]
            elif item.find("{http://www.itunes.com/dtds/podcast-1.0.dtd}enclosure") is not None:
                enc = item.find("{http://www.itunes.com/dtds/podcast-1.0.dtd}enclosure")
                if enc is not None and "url" in enc.attrib:
                    audio_url = enc.attrib["url"]

            if not audio_url:
                continue

            # Duration
            duration_str = (item.findtext("{http://www.itunes.com/dtds/podcast-1.0.dtd}duration") or "0").strip()
            duration_sec = self._parse_duration(duration_str)

            # Generate stable episode id
            ep_id = f"{feed_id}_{abs(hash(guid or audio_url)) % 100000000:08d}"

            episodes.append({
                "id": ep_id,
                "feed_id": feed_id,
                "guid": guid,
                "title": ep_title,
                "audio_url": audio_url,
                "duration": duration_sec,
                "pub_date": pub_date,
                "shownotes": shownotes,
                "status": "ready",
                "progress": 0,
                "error_message": None,
                "gdrive_folder_id": None
            })

        return {
            "feed": {
                "id": feed_id,
                "source_type": "apple_rss",
                "title": title,
                "author": author,
                "cover_url": cover_url,
                "description": description
            },
            "episodes": episodes
        }

    def _parse_duration(self, dur: str) -> int:
        if not dur:
            return 0
        if dur.isdigit():
            return int(dur)
        parts = dur.split(":")
        try:
            if len(parts) == 3:
                return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])
            elif len(parts) == 2:
                return int(parts[0]) * 60 + int(parts[1])
        except (ValueError, TypeError):
            pass
        return 0

    async def fetch_and_parse_feed(self, feed_url: str, feed_id: str) -> Dict[str, Any]:
        """Fetch RSS feed by URL and parse it."""
        async with httpx.AsyncClient(timeout=self.timeout, follow_redirects=True) as client:
            resp = await client.get(feed_url, headers={"User-Agent": "AmberPodcast/1.0"})
            resp.raise_for_status()
            return self.parse_rss_xml(resp.text, feed_id)

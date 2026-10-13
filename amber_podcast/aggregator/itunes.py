import httpx
import xml.etree.ElementTree as ET
import re
from typing import List, Dict, Any, Optional
from urllib.parse import quote

class ApplePodcastAggregator:
    def __init__(self, timeout: float = 15.0):
        self.timeout = timeout

    async def search_podcasts(self, query: str, limit: int = 15, country: str = "us") -> List[Dict[str, Any]]:
        """Search Apple Podcasts Directory API for shows."""
        url = f"https://itunes.apple.com/search?term={quote(query)}&entity=podcast&country={country}&limit={limit}"
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            data = resp.json()

        results = []
        for item in data.get("results", []):
            results.append({
                "source_type": "apple_rss",
                "collection_id": str(item.get("collectionId")),
                "title": item.get("collectionName", ""),
                "author": item.get("artistName", ""),
                "feed_url": item.get("feedUrl", ""),
                "cover_url": item.get("artworkUrl600", item.get("artworkUrl100", "")),
                "genre": item.get("primaryGenreName", ""),
                "track_count": item.get("trackCount", 0)
            })
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
                "shownotes": shownotes
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

import os
import asyncio
import logging
import time
import hashlib
import re
from contextlib import asynccontextmanager
from email.utils import parsedate_to_datetime
from typing import Optional, List, Dict, Any
from pathlib import Path
from fastapi import FastAPI, Depends, HTTPException, Header, Query, BackgroundTasks, status
from fastapi.responses import JSONResponse, FileResponse, StreamingResponse, RedirectResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

logger = logging.getLogger("amber_podcast")

def stable_hash(s: str) -> str:
    """稳定的 8 位数字 hash（跨进程一致），替代 Python 内置 hash()。

    Python 内置 hash(str) 受 PYTHONHASHSEED 随机化影响，每次进程启动结果不同，
    会导致同一 URL/guid 生成不同的 feed_id/episode_id，触发重复订阅与外键约束失败。
    """
    return f"{int(hashlib.sha256(s.encode('utf-8')).hexdigest(), 16) % 100000000:08d}"

def _pub_ts(pub_date: Optional[str]) -> Optional[int]:
    """Parse an RFC 822 podcast pub_date into a unix timestamp.

    ``episodes.pub_date`` is stored as TEXT, so SQL's ``ORDER BY pub_date``
    sorts it lexicographically ("Mon, 9" < "Sun, 8") and cannot be trusted for
    recency. Compare parsed timestamps instead. Returns None when unparseable.
    """
    if not pub_date:
        return None
    try:
        return int(parsedate_to_datetime(pub_date).timestamp())
    except (TypeError, ValueError, OverflowError):
        return None

from amber_podcast.config import AUTH_TOKEN, SERVER_HOST, SERVER_PORT, GDRIVE_DIR, DATA_DIR, SCRATCH_DIR
from amber_podcast.database import Database
from amber_podcast.aggregator.itunes import ApplePodcastAggregator
from amber_podcast.aggregator.xiaoyuzhou import XiaoyuzhouAggregator
from amber_podcast.pipeline.asr import ASREngine, ASRSegment
from amber_podcast.pipeline.translator import TranslatorEngine
from amber_podcast.pipeline.tts.edge import EdgeTTSProvider
from amber_podcast.pipeline.tts.google_cloud import GoogleCloudTTSProvider
from amber_podcast.pipeline.aligner import AlignmentEngine
from amber_podcast.pipeline.archiver import EpisodeArchiver

# Feed polling: the server is the only writer of new episodes, so this is a
# single in-process loop (uvicorn runs one worker here). New drops from an
# auto_translate feed are queued for the pipeline immediately.
POLL_INTERVAL_SEC = int(os.environ.get("AMBER_POLL_INTERVAL", "1800"))
POLL_STARTUP_DELAY_SEC = int(os.environ.get("AMBER_POLL_STARTUP_DELAY", "60"))

# User-tunable pipeline settings, persisted as TEXT rows in the settings table.
# These are the only keys PUT /api/v1/settings accepts.
DEFAULT_SETTINGS: Dict[str, str] = {
    "auto_translate_default": "0",    # newly subscribed feeds auto-transcribe
    "poll_interval_sec": "1800",      # how often subscribed feeds are refreshed
    "max_concurrent_pipelines": "1",  # dumps allowed to run at the same time
}


def _get_setting(key: str, default: Optional[str] = None) -> str:
    try:
        stored = db.get_settings()
    except Exception:
        stored = {}
    if key in stored:
        return stored[key]
    if default is not None:
        return default
    return DEFAULT_SETTINGS.get(key, "")


def _int_setting(key: str, fallback: int, minimum: int = 1) -> int:
    try:
        return max(minimum, int(_get_setting(key)))
    except (TypeError, ValueError):
        return fallback


@asynccontextmanager
async def lifespan(app):
    poller = asyncio.create_task(_poll_loop())
    try:
        yield
    finally:
        poller.cancel()


app = FastAPI(title="Amber Podcast API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

db = Database()
apple_agg = ApplePodcastAggregator()
xyz_agg = XiaoyuzhouAggregator()


async def _poll_loop():
    """Periodically refresh every subscribed feed. The interval is re-read each
    cycle so a settings change takes effect without a restart."""
    await asyncio.sleep(POLL_STARTUP_DELAY_SEC)
    while True:
        try:
            await _poll_all_feeds()
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("feed poll cycle failed")
        await asyncio.sleep(_int_setting("poll_interval_sec", POLL_INTERVAL_SEC, minimum=60))


async def _poll_all_feeds() -> List[str]:
    """One poll cycle. Returns ids of episodes discovered for the first time.

    A failed feed is logged and skipped — one dead RSS URL must not stop the
    others from being refreshed.
    """
    new_episode_ids: List[str] = []
    for feed in db.list_feeds():
        try:
            data = await apple_agg.fetch_and_parse_feed(feed["feed_url"], feed["id"])
        except Exception as exc:
            logger.warning("poll: feed %s failed: %s", feed["id"], exc)
            continue

        for ep in data.get("episodes", []):
            # Reuse the stored id when this guid is already known: id derivation
            # changed historically, so trusting ep["id"] would re-insert the
            # whole back-catalogue on every poll.
            existing = db.get_episode_by_guid(feed["id"], ep.get("guid") or "")
            episode_id = existing["id"] if existing else ep["id"]
            db.upsert_episode(
                episode_id=episode_id,
                feed_id=feed["id"],
                title=ep["title"],
                audio_url=ep["audio_url"],
                duration=ep["duration"],
                pub_date=ep["pub_date"],
                shownotes=ep["shownotes"],
                guid=ep["guid"],
            )
            if existing is None:
                new_episode_ids.append(episode_id)

    queued = _queue_auto_translations(new_episode_ids)
    if new_episode_ids:
        logger.info("poll: %d new episodes, %d queued for transcription",
                    len(new_episode_ids), queued)
    return new_episode_ids


def _active_pipeline_count() -> int:
    return len(db.list_episodes_by_statuses(
        ["pending", "transcribing", "translating", "synthesizing"], limit=1000))


def _enqueue_pipeline(episode_id: str) -> bool:
    """Mark an episode pending and launch the pipeline, respecting the concurrency cap.

    Returns False (leaving the episode idle) when the cap is reached — the next
    poll cycle picks it up, so nothing is lost and we never stampede the box.
    """
    limit = _int_setting("max_concurrent_pipelines", 1)
    if _active_pipeline_count() >= limit:
        return False
    db.update_episode_status(episode_id, status="pending", progress=0)
    asyncio.create_task(run_pipeline_task(episode_id))
    return True


def _queue_auto_translations(episode_ids: List[str]) -> int:
    """Queue newly discovered episodes for the pipeline — once, and only when
    the feed opted into auto_translate and the drop postdates the subscription.
    """
    queued = 0
    for eid in episode_ids:
        ep = db.get_episode(eid)
        if not ep or ep.get("status") != "idle":
            continue  # already running/finished, or a duplicate from an overlap
        feed = db.get_feed(ep["feed_id"])
        if not feed or not feed.get("auto_translate"):
            continue
        if (_pub_ts(ep.get("pub_date")) or 0) <= feed["created_at"]:
            continue  # back-catalogue drop: never auto-transcribe pre-subscribe content
        if _enqueue_pipeline(eid):
            queued += 1
    return queued


archiver = EpisodeArchiver()

# Auth dependency
def verify_token(authorization: Optional[str] = Header(None)) -> str:
    if not authorization:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Missing Authorization header")
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or token != AUTH_TOKEN:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token")
    return token

# --- Pydantic Request Models ---
class SubscribeRequest(BaseModel):
    url: str
    auto_translate: bool = False

class ProgressUpdateRequest(BaseModel):
    episode_id: str
    position_ms: int
    duration_ms: int
    track_mode: str = "chinese"  # "original", "chinese", "alternating"
    is_finished: bool = False

# --- Endpoints ---

@app.get("/health")
def health():
    return {"status": "ok", "app": "amber-podcast", "version": "0.1.0"}

@app.api_route("/download/AmberPodcast.ipa", methods=["GET", "HEAD"])
def download_ipa():
    ipa_path = Path("/root/projects/amber-podcast/dist/AmberPodcast.ipa")
    if not ipa_path.exists():
        raise HTTPException(status_code=404, detail="IPA not found on server")
    return FileResponse(
        path=str(ipa_path),
        media_type="application/octet-stream",
        filename="AmberPodcast.ipa"
    )

@app.get("/api/v1/search")
async def search_podcasts(
    q: str = Query(..., min_length=1),
    limit: int = 15,
    country: Optional[str] = Query(None),
    token: str = Depends(verify_token)
):
    """Search for podcasts across Apple Podcasts Directory (supports dual CN+US indexing)."""
    try:
        results = await apple_agg.search_podcasts(query=q, limit=limit, country=country)
        return {"query": q, "results": results}
    except Exception as e:
        logger.error(f"Search endpoint error for query '{q}': {e}")
        return {"query": q, "results": []}

_ephemeral_feed_cache: Dict[str, Dict[str, Any]] = {}

@app.get("/api/v1/discover")
async def get_discover_feed(token: str = Depends(verify_token)):
    """Curated and real-time Apple Podcasts discovery feed with featured carousels, top Chinese/global charts."""
    # 1. Fetch real-time Top Chinese and Global podcasts from Apple Podcasts
    top_cn = await apple_agg.fetch_top_podcasts(country="cn", limit=20)
    top_us = await apple_agg.fetch_top_podcasts(country="us", limit=20)

    # 2. Curated Editorial Spotlight (High quality shows with verified active feeds)
    featured = [
        {
            "id": "1183662640",
            "collection_id": "1183662640",
            "source_type": "apple_rss",
            "title": "声东击西",
            "author": "ETW Studio",
            "feed_url": "https://feeds.fireside.fm/shengdongjixi/rss",
            "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/34/fe/fd/34fefd10-2039-380d-7015-dbc28b79f625/mza_7380566725793754773.jpg/600x600bb.jpg",
            "description": "带你看不一样的世界 · 深度跨文化对谈",
            "genre": "深度对谈",
            "editorial_tag": "本周聚焦 · 思想沙龙",
            "track_count": 435,
            "auto_translate": 0
        },
        {
            "id": "1545953110",
            "collection_id": "1545953110",
            "source_type": "apple_rss",
            "title": "Huberman Lab",
            "author": "Dr. Andrew Huberman",
            "feed_url": "https://feeds.megaphone.fm/hubermanlab",
            "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/9a/d3/19/9ad31912-0b5a-a16e-2d7c-9fd074698b9c/mza_8994222203629500925.jpg/600x600bb.jpg",
            "description": "神经科学机制、多巴胺架构与日常认知协议",
            "genre": "健康科学",
            "editorial_tag": "全球顶流 · 双轨精译",
            "track_count": 456,
            "auto_translate": 1
        },
        {
            "id": "1434243584",
            "collection_id": "1434243584",
            "source_type": "apple_rss",
            "title": "Lex Fridman Podcast",
            "author": "Lex Fridman",
            "feed_url": "https://lexfridman.com/feed/podcast/",
            "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/2c/3d/62/2c3d623e-63f5-7e04-37a5-c7e6822262ea/mza_14389689408611956162.jpg/600x600bb.jpg",
            "description": "关于人工智能、前沿科学、意识哲学与人类命运的对话",
            "genre": "科技·AI",
            "editorial_tag": "硬核访谈 · 智能时代",
            "track_count": 503,
            "auto_translate": 1
        },
        {
            "id": "1050462261",
            "collection_id": "1050462261",
            "source_type": "apple_rss",
            "title": "Acquired",
            "author": "Ben Gilbert and David Rosenthal",
            "feed_url": "https://acquired.libsyn.com/rss",
            "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/e0/75/eb/e075ebc0-0bb5-2d4e-fb06-1875c742c38f/mza_13491410191834246830.jpg/600x600bb.jpg",
            "description": "深度复盘科技巨头与时代商业帝国的诞生编年史",
            "genre": "商业商业",
            "editorial_tag": "独家深度 · 商业史诗",
            "track_count": 218,
            "auto_translate": 1
        }
    ]

    # Fallback to curated if live RSS is empty
    if not top_cn:
        top_cn = [
            {
                "id": "1455784513",
                "collection_id": "1455784513",
                "source_type": "apple_rss",
                "title": "凹凸电波",
                "author": "凹凸电波",
                "feed_url": "http://www.ximalaya.com/album/19206382.xml",
                "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts113/v4/30/24/93/302493e7-be1c-958c-366e-8d13c2fc698c/mza_10993420535667969042.jpg/600x600bb.jpg",
                "description": "都市青年生活指南与无厘头欢乐对谈",
                "genre": "生活娱乐",
                "track_count": 300,
                "auto_translate": 0
            },
            {
                "id": "1573189055",
                "collection_id": "1573189055",
                "source_type": "apple_rss",
                "title": "声动早咖啡",
                "author": "声动活泼",
                "feed_url": "https://www.ximalaya.com/album/51076156.xml",
                "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts112/v4/a9/7f/7a/a97f7a8f-4451-05bc-bacc-637773b1b06a/mza_16067595309054880476.png/600x600bb.jpg",
                "description": "用 15 分钟为你的早晨充电，速览全球商业与科技动态",
                "genre": "商业资讯",
                "track_count": 780,
                "auto_translate": 0
            },
            {
                "id": "1668626930",
                "collection_id": "1668626930",
                "source_type": "apple_rss",
                "title": "霓达播客",
                "author": "霓达播台NidaMedia",
                "feed_url": "https://feed.xyzfm.space/xlgejk3wbj8q",
                "cover_url": "https://image.xyzcdn.net/Fh6Ms1Ed-iAP4UL-4wjV6DYYtg6c.jpg",
                "description": "真实罪案、法医探案与社会派故事深度剖析",
                "genre": "真实故事",
                "track_count": 165,
                "auto_translate": 0
            }
        ]

    if not top_us:
        top_us = [
            featured[1],
            featured[2],
            featured[3],
            {
                "id": "360084272",
                "collection_id": "360084272",
                "source_type": "apple_rss",
                "title": "The Joe Rogan Experience",
                "author": "Joe Rogan",
                "feed_url": "https://feeds.megaphone.fm/GLT1412515089",
                "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts125/v4/0e/86/e3/0e86e3f2-1f3c-5872-6807-6bbd688cf292/mza_1271105436660161476.jpg/600x600bb.jpg",
                "description": "Long-form conversations with comedians, scientists, fighters and thinkers.",
                "genre": "Comedy & Culture",
                "track_count": 2200,
                "auto_translate": 1
            }
        ]

    # Save to ephemeral cache to help episode preview resolution
    for item in featured + top_cn + top_us:
        fid = str(item.get("id") or item.get("collection_id") or "")
        furl = item.get("feed_url")
        if fid and furl:
            _ephemeral_feed_cache[fid] = {"ts": time.time(), "feed_url": furl, "meta": item}

    return {
        "featured": featured,
        "top_chinese": top_cn,
        "top_global": top_us
    }

@app.post("/api/v1/feeds/subscribe")
async def subscribe_feed(
    req: SubscribeRequest,
    token: str = Depends(verify_token)
):
    """Subscribe to a podcast URL (Apple RSS or Xiaoyuzhou)."""
    try:
        return await _subscribe_impl(req)
    except HTTPException:
        raise
    except Exception as exc:
        logger.warning(
            "Subscribe failed url=%s: %s: %s",
            req.url, type(exc).__name__, exc
        )
        raise HTTPException(
            status_code=400,
            detail=f"无法订阅该地址（{type(exc).__name__}）"
        )


async def _subscribe_impl(req: SubscribeRequest):
    """Subscription logic, wrapped by subscribe_feed for error normalization."""
    url = req.url.strip()
    if "xiaoyuzhoufm.com" in url:
        # Xiaoyuzhou link
        if "/episode/" in url:
            data = await xyz_agg.fetch_episode(url)
            feed_info = data["feed"]
            feed = db.upsert_feed(
                feed_id=feed_info["id"],
                source_type="xiaoyuzhou",
                title=feed_info["title"],
                author=feed_info["author"],
                feed_url=url,
                cover_url=feed_info["cover_url"],
                description=feed_info["description"],
                auto_translate=1 if req.auto_translate else _int_setting("auto_translate_default", 0, minimum=0)
            )
            ep = data["episode"]
            db.upsert_episode(
                episode_id=ep["id"],
                feed_id=feed_info["id"],
                title=ep["title"],
                audio_url=ep["audio_url"],
                duration=ep["duration"],
                pub_date=ep["pub_date"],
                shownotes=ep["shownotes"],
                guid=ep["guid"]
            )
            return {"feed": feed, "episode_count": 1}
        else:
            data = await xyz_agg.fetch_podcast_episodes(url)
            feed_info = data["feed"]
            feed = db.upsert_feed(
                feed_id=feed_info["id"],
                source_type="xiaoyuzhou",
                title=feed_info["title"],
                author=feed_info["author"],
                feed_url=url,
                cover_url=feed_info["cover_url"],
                description=feed_info["description"],
                auto_translate=1 if req.auto_translate else _int_setting("auto_translate_default", 0, minimum=0)
            )
            for ep in data.get("episodes", []):
                db.upsert_episode(
                    episode_id=ep["id"],
                    feed_id=feed_info["id"],
                    title=ep["title"],
                    audio_url=ep["audio_url"],
                    duration=ep["duration"],
                    pub_date=ep["pub_date"],
                    shownotes=ep["shownotes"],
                    guid=ep["guid"]
                )
            return {"feed": feed, "episode_count": len(data.get("episodes", []))}
    else:
        # Standard RSS feed
        feed_id = f"feed_rss_{stable_hash(url)}"
        existing = db.get_feed_by_url(url)
        if existing:
            feed_id = existing["id"]  # 复用已有 feed id，保证幂等（避免重复订阅产生重复记录）
        data = await apple_agg.fetch_and_parse_feed(url, feed_id)
        feed_info = data["feed"]
        feed = db.upsert_feed(
            feed_id=feed_id,
            source_type="apple_rss",
            title=feed_info["title"],
            author=feed_info["author"],
            feed_url=url,
            cover_url=feed_info["cover_url"],
            description=feed_info["description"],
            auto_translate=1 if req.auto_translate else 0
        )
        for ep in data.get("episodes", []):
            db.upsert_episode(
                episode_id=ep["id"],
                feed_id=feed_id,
                title=ep["title"],
                audio_url=ep["audio_url"],
                duration=ep["duration"],
                pub_date=ep["pub_date"],
                shownotes=ep["shownotes"],
                guid=ep["guid"]
            )
        return {"feed": feed, "episode_count": len(data.get("episodes", []))}

@app.get("/api/v1/feeds")
def list_feeds(token: str = Depends(verify_token)):
    """List all subscribed podcasts."""
    return {"feeds": db.list_feeds()}

def _pick_hero_episode(feeds: List[Dict[str, Any]], episodes: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """Newest episode published *after* its own feed was subscribed.

    A freshly added podcast must not push its back-catalogue into the hero —
    only genuinely new drops qualify. ``pub_ts`` (numeric) is preferred over
    parsing ``pub_date`` (TEXT) because the latter sorts lexicographically.
    """
    created_by_feed = {f["id"]: f["created_at"] for f in feeds}
    hero = None
    hero_ts = None
    for ep in episodes:
        subscribed_at = created_by_feed.get(ep["feed_id"])
        pub_ts = ep.get("pub_ts") or _pub_ts(ep.get("pub_date"))
        if subscribed_at is None or not pub_ts or pub_ts < subscribed_at:
            continue
        if hero_ts is None or pub_ts > hero_ts:
            hero_ts = pub_ts
            hero = ep
    return hero


@app.get("/api/v1/library")
def get_library(token: str = Depends(verify_token)):
    """Subscribed podcasts + latest 30 episodes + the hero episode.

    ``hero_episode`` is the newest episode published after its feed was
    subscribed; it is null when nothing new has arrived yet, and the client
    collapses the hero in that case. ``recent_episodes`` is left unfiltered:
    the "continue listening" shelf still shows the whole recent window.
    """
    feeds = db.list_feeds()
    recent_episodes = db.list_episodes(feed_id=None, limit=30)
    return {
        "feeds": feeds,
        "recent_episodes": recent_episodes,
        "hero_episode": _pick_hero_episode(feeds, recent_episodes),
    }

@app.api_route("/api/v1/images/proxy", methods=["GET", "HEAD"])
async def proxy_image(url: str = Query(...), w: int = Query(1200, ge=100, le=3000)):
    """Proxy, compress, and cache external podcast cover images (resolving CDN timeouts and mobile network slowness)."""
    clean_url = url.strip()
    if not clean_url:
        raise HTTPException(status_code=400, detail="Missing url")

    cache_dir = SCRATCH_DIR / "images"
    cache_dir.mkdir(parents=True, exist_ok=True)

    import hashlib
    url_hash = hashlib.md5(f"{clean_url}_w{w}".encode("utf-8")).hexdigest()
    cached_file = cache_dir / f"{url_hash}.jpg"

    headers = {
        "Cache-Control": "public, max-age=31536000, immutable",
        "Access-Control-Allow-Origin": "*"
    }

    def get_placeholder():
        ph = cache_dir / "acoustic_placeholder.jpg"
        if not ph.exists():
            try:
                from PIL import Image, ImageDraw
                img = Image.new("RGB", (w, w), color="#18181b")
                draw = ImageDraw.Draw(img)
                heights = [30, 60, 95, 140, 180, 210, 190, 150, 110, 70, 45, 25]
                for i, h in enumerate(heights):
                    x = int(w * 0.22) + i * 24
                    draw.rounded_rectangle([x, w//2 - h//2, x + 12, w//2 + h//2], radius=6, fill="#d4a373")
                img.save(str(ph), "JPEG", quality=85)
            except Exception:
                pass
        return ph

    if cached_file.exists() and cached_file.stat().st_size > 0:
        return FileResponse(str(cached_file), media_type="image/jpeg", headers=headers)

    import httpx
    from PIL import Image
    try:
        async with httpx.AsyncClient(timeout=12.0, follow_redirects=True) as client:
            resp = await client.get(clean_url)
            if resp.status_code == 200:
                raw_bytes = resp.content
                import io
                try:
                    img = Image.open(io.BytesIO(raw_bytes))
                    img.thumbnail((w, w), Image.Resampling.LANCZOS)
                    img.convert("RGB").save(str(cached_file), "JPEG", quality=90, optimize=True)
                except Exception as e:
                    logger.warning(f"PIL compression failed for {clean_url}: {e}, saving raw")
                    with open(cached_file, "wb") as f:
                        f.write(raw_bytes)

                return FileResponse(str(cached_file), media_type="image/jpeg", headers=headers)
            else:
                ph = get_placeholder()
                if ph.exists():
                    return FileResponse(str(ph), media_type="image/jpeg", headers=headers)
    except Exception as e:
        logger.warning(f"Image proxy failed for {clean_url}: {e}")
        ph = get_placeholder()
        if ph.exists():
            return FileResponse(str(ph), media_type="image/jpeg", headers=headers)

    return RedirectResponse(url=clean_url)

@app.delete("/api/v1/feeds/{feed_id}")
def delete_feed(feed_id: str, token: str = Depends(verify_token)):
    """Unsubscribe from a podcast feed."""
    success = db.delete_feed(feed_id)
    if not success:
        raise HTTPException(status_code=404, detail="Feed not found")
    return {"success": True, "feed_id": feed_id}

@app.get("/api/v1/feeds/preview")
async def preview_feed(
    url: str = Query(...),
    token: str = Depends(verify_token)
):
    """Dynamically parse and preview a podcast feed without requiring subscription."""
    clean_url = url.strip()
    if not clean_url:
        raise HTTPException(status_code=400, detail="Empty feed url")
    
    feed_id = f"preview_{stable_hash(clean_url)}"
    if clean_url in _ephemeral_feed_cache and "parsed" in _ephemeral_feed_cache[clean_url]:
        entry = _ephemeral_feed_cache[clean_url]
        if time.time() - entry["ts"] < 1800:
            return entry["parsed"]

    try:
        if "xiaoyuzhoufm.com" in clean_url:
            data = await xyz_agg.fetch_podcast_episodes(clean_url)
        else:
            data = await apple_agg.fetch_and_parse_feed(clean_url, feed_id)
        _ephemeral_feed_cache[clean_url] = {"ts": time.time(), "parsed": data}
        return data
    except Exception as e:
        logger.error(f"Preview feed error for {clean_url}: {e}")
        raise HTTPException(status_code=500, detail=f"Failed to parse feed: {e}")

@app.get("/api/v1/feeds/{feed_id}/episodes")
async def list_feed_episodes(
    feed_id: str,
    feed_url: Optional[str] = Query(None),
    limit: int = 50,
    offset: int = 0,
    token: str = Depends(verify_token)
):
    """List episodes for a given feed. Automatically previews unsubscribed/discover feeds."""
    episodes = db.list_episodes(feed_id=feed_id, limit=limit, offset=offset)
    if episodes:
        return {"feed_id": feed_id, "episodes": episodes, "is_preview": False}

    target_url = feed_url
    if not target_url and feed_id in _ephemeral_feed_cache:
        target_url = _ephemeral_feed_cache[feed_id].get("feed_url")

    if not target_url and feed_id.isdigit():
        try:
            looked_up = await apple_agg.lookup_podcasts_batch([feed_id])
            if looked_up and looked_up[0].get("feed_url"):
                target_url = looked_up[0]["feed_url"]
        except Exception as e:
            logger.warning(f"Auto-lookup failed for feed_id {feed_id}: {e}")

    if target_url:
        try:
            if target_url in _ephemeral_feed_cache and "parsed" in _ephemeral_feed_cache[target_url]:
                entry = _ephemeral_feed_cache[target_url]
                if time.time() - entry["ts"] < 1800:
                    p_eps = entry["parsed"].get("episodes", [])
                    return {"feed_id": feed_id, "episodes": p_eps[offset:offset+limit], "is_preview": True}

            if "xiaoyuzhoufm.com" in target_url:
                parsed = await xyz_agg.fetch_podcast_episodes(target_url)
            else:
                parsed = await apple_agg.fetch_and_parse_feed(target_url, feed_id)
            _ephemeral_feed_cache[target_url] = {"ts": time.time(), "parsed": parsed}
            p_eps = parsed.get("episodes", [])
            return {"feed_id": feed_id, "episodes": p_eps[offset:offset+limit], "is_preview": True}
        except Exception as e:
            logger.warning(f"Failed to auto-parse episodes for feed {feed_id} from {target_url}: {e}")

    return {"feed_id": feed_id, "episodes": [], "is_preview": True}

@app.get("/api/v1/episodes/{episode_id}")
def get_episode_detail(episode_id: str, token: str = Depends(verify_token)):
    """Get single episode metadata and processing state."""
    ep = db.get_episode(episode_id)
    if not ep:
        raise HTTPException(status_code=404, detail="Episode not found")
    progress = db.get_playback_progress(episode_id)
    return {"episode": ep, "playback_progress": progress}

# --- Asynchronous Pipeline Execution ---

async def run_pipeline_task(episode_id: str):
    """Background worker executing the full ASR -> Translate -> TTS -> Alignment -> Archive pipeline."""
    ep = db.get_episode(episode_id)
    if not ep:
        return

    db.mark_dump_started(episode_id)

    work_dir = SCRATCH_DIR / episode_id
    work_dir.mkdir(parents=True, exist_ok=True)
    audio_path = str(work_dir / "original.mp3")

    try:
        # Step 1: Download original audio
        db.update_episode_status(episode_id, status="transcribing", progress=10)
        import httpx
        async with httpx.AsyncClient(timeout=180.0, follow_redirects=True) as client:
            resp = await client.get(ep["audio_url"])
            resp.raise_for_status()
            with open(audio_path, "wb") as f:
                f.write(resp.content)

        # Step 2: Language detection & routing
        is_chinese = any('\u4e00' <= c <= '\u9fff' for c in ep.get("title", "")) or ep.get("feed_id", "").startswith("xyz_")
        if is_chinese:
            logger.info(f"Episode {episode_id} is native Chinese podcast. Executing ASR subtitle extraction & AI notes.")
            db.update_episode_status(episode_id, status="transcribing", progress=30)
            asr_engine = ASREngine()
            asr_segments = await asr_engine.transcribe_audio_file(audio_path, language="zh")

            db.update_episode_status(episode_id, status="translating", progress=65)
            translator = TranslatorEngine()
            chapters_notes = await translator.generate_chapters_and_notes(asr_segments)

            timing_sync = []
            full_mapping = []
            for idx, seg in enumerate(asr_segments):
                speaker = getattr(seg, "speaker", "Speaker") or "Speaker"
                start = getattr(seg, "start", 0.0)
                end = getattr(seg, "end", 0.0)
                text = getattr(seg, "text", "")
                t_seg = {
                    "id": idx,
                    "speaker": speaker,
                    "en": {"start": start, "end": end},
                    "zh": {"start": start, "end": end}
                }
                timing_sync.append(t_seg)
                m_seg = {
                    "index": idx,
                    "speaker": speaker,
                    "en_text": text,
                    "zh_display": text,
                    "zh_spoken": text,
                    "en_range": {"start": start, "end": end},
                    "zh_range": {"start": start, "end": end},
                    "en_words": None,
                    "zh_words": None
                }
                full_mapping.append(m_seg)

            timing_path = str(work_dir / "timing_sync.json")
            mapping_path = str(work_dir / "full_mapping.json")
            import json
            with open(timing_path, "w", encoding="utf-8") as f:
                json.dump(timing_sync, f, ensure_ascii=False, indent=2)
            with open(mapping_path, "w", encoding="utf-8") as f:
                json.dump(full_mapping, f, ensure_ascii=False, indent=2)

            db.update_episode_status(episode_id, status="synthesizing", progress=90)
            archiver.archive_episode_bundle(
                episode_id=episode_id,
                original_audio_path=audio_path,
                chinese_audio_path=audio_path,
                timing_sync_path=timing_path,
                full_mapping_path=mapping_path,
                chapters=chapters_notes.get("chapters"),
                article_markdown=chapters_notes.get("article_markdown")
            )
            db.update_episode_status(episode_id, status="ready", progress=100)
            return

        # Step 2: ASR Transcription (Foreign Podcast)
        db.update_episode_status(episode_id, status="transcribing", progress=25)
        asr_engine = ASREngine()
        asr_segments = await asr_engine.transcribe_audio_file(audio_path)

        # Step 3: LLM Oral Translation & Chapters
        db.update_episode_status(episode_id, status="translating", progress=50)
        translator = TranslatorEngine()
        trans_segments = await translator.translate_segments(asr_segments)
        chapters_notes = await translator.generate_chapters_and_notes(asr_segments)

        # Step 4: TTS Synthesis & Alignment
        db.update_episode_status(episode_id, status="synthesizing", progress=75)
        # Use EdgeTTSProvider as default reliable multi-speaker synthesis engine
        tts_provider = EdgeTTSProvider()
        aligner = AlignmentEngine(tts_provider=tts_provider)
        dual_bundle = await aligner.build_dual_track_bundle(episode_id, trans_segments, work_dir=work_dir)

        # Step 5: Archive to Google Drive
        db.update_episode_status(episode_id, status="synthesizing", progress=90)
        archiver.archive_episode_bundle(
            episode_id=episode_id,
            original_audio_path=audio_path,
            chinese_audio_path=dual_bundle["chinese_audio_path"],
            timing_sync_path=dual_bundle["timing_sync_path"],
            full_mapping_path=dual_bundle["full_mapping_path"],
            chapters=chapters_notes.get("chapters"),
            article_markdown=chapters_notes.get("article_markdown")
        )

        # Mark ready
        db.update_episode_status(episode_id, status="ready", progress=100)

    except Exception as e:
        db.update_episode_status(episode_id, status="failed", progress=0, error_message=str(e))

@app.post("/api/v1/episodes/{episode_id}/translate")
async def trigger_translation(
    episode_id: str,
    bg_tasks: BackgroundTasks,
    payload: Optional[Dict[str, Any]] = None,
    token: str = Depends(verify_token)
):
    """Trigger background dual-track AI translation / Chinese subtitle alignment for an episode."""
    ep = db.get_episode(episode_id)
    if not ep and payload and "episode" in payload:
        ep_dict = payload["episode"]
        feed_dict = payload.get("feed")
        fid = ep_dict.get("feed_id") or ep_dict.get("feedId") or (episode_id.split("_")[0] if "_" in episode_id else "unknown_feed")
        if not db.get_feed(fid):
            feed_meta = feed_dict or {}
            title = feed_meta.get("title") or "未知播客"
            author = feed_meta.get("author") or ""
            cover = feed_meta.get("cover_url") or feed_meta.get("coverUrl") or ""
            furl = feed_meta.get("feed_url") or feed_meta.get("feedUrl") or ""
            db.upsert_feed(
                feed_id=fid,
                source_type="apple_rss",
                title=title,
                author=author,
                feed_url=furl,
                cover_url=cover,
                description=""
            )
        db.upsert_episode(
            episode_id=episode_id,
            feed_id=fid,
            guid=ep_dict.get("guid") or episode_id,
            title=ep_dict.get("title") or "单集",
            audio_url=ep_dict.get("audio_url") or ep_dict.get("audioUrl") or "",
            duration=ep_dict.get("duration") or 0,
            pub_date=ep_dict.get("pub_date") or ep_dict.get("pubDate") or "",
            shownotes=ep_dict.get("shownotes") or ""
        )
        ep = db.get_episode(episode_id)

    if not ep and "_" in episode_id:
        fid = episode_id.split("_")[0]
        try:
            eps_data = await list_feed_episodes(feed_id=fid)
            for item in eps_data.get("episodes", []):
                if item.get("id") == episode_id:
                    db.upsert_episode(
                        episode_id=episode_id,
                        feed_id=fid,
                        guid=item.get("guid") or episode_id,
                        title=item.get("title") or "单集",
                        audio_url=item.get("audio_url") or "",
                        duration=item.get("duration") or 0,
                        pub_date=item.get("pub_date") or "",
                        shownotes=item.get("shownotes") or ""
                    )
                    ep = db.get_episode(episode_id)
                    break
        except Exception as ex:
            logger.warning(f"Failed to auto-ingest episode {episode_id}: {ex}")

    if not ep:
        raise HTTPException(status_code=404, detail="Episode not found and could not be auto-resolved")

    if ep["status"] in ["transcribing", "translating", "synthesizing"]:
        return {"status": ep["status"], "progress": ep["progress"], "message": "Translation already in progress"}

    db.update_episode_status(episode_id, status="pending", progress=0)
    bg_tasks.add_task(run_pipeline_task, episode_id)
    return {"status": "pending", "episode_id": episode_id, "message": "Translation task queued"}

@app.get("/api/v1/pipeline/status")
def get_pipeline_status(token: str = Depends(verify_token)):
    """Return real-time status of audio dump, ASR transcription, translation, and archive tasks."""
    # Full window: the library can exceed 1k episodes, and a limit here would
    # silently drop older failed/ready rows from the per-podcast groups.
    all_episodes = db.list_episodes(limit=5000)
    feeds = db.list_feeds()
    feed_map = {f["id"]: f for f in feeds}

    def enrich(ep: Dict[str, Any]) -> Dict[str, Any]:
        d = dict(ep)
        d["feed_title"] = feed_map.get(ep.get("feed_id", ""), {}).get("title", "未知播客")
        return d

    active = [enrich(ep) for ep in all_episodes if ep.get("status") in ["pending", "transcribing", "translating", "synthesizing"]]
    ready = [enrich(ep) for ep in all_episodes if ep.get("status") == "ready"]
    failed = [enrich(ep) for ep in all_episodes if ep.get("status") == "failed"]
    idle = [ep for ep in all_episodes if ep.get("status") == "idle"]

    # 按播客（feed）分组，供前端「按播客分类」展示
    by_feed: Dict[str, Dict[str, Any]] = {}
    for ep in all_episodes:
        fid = ep.get("feed_id", "") or "unknown"
        if fid not in by_feed:
            meta = feed_map.get(fid, {})
            by_feed[fid] = {
                "feed_id": fid,
                "feed_title": meta.get("title", "未知播客"),
                "cover_url": meta.get("cover_url", ""),
                "episodes": [],
            }
        by_feed[fid]["episodes"].append(enrich(ep))

    feeds_grouped = sorted(by_feed.values(), key=lambda f: f["feed_title"])

    archive_dir = DATA_DIR / "archive"
    storage_bytes = sum(f.stat().st_size for f in archive_dir.rglob("*") if f.is_file()) if archive_dir.exists() else 0

    return {
        "summary": {
            "active_count": len(active),
            "ready_count": len(ready),
            "failed_count": len(failed),
            "idle_count": len(idle),
            "storage_mb": round(storage_bytes / (1024 * 1024), 2),
            "asr_engine": "Groq Whisper Large-v3 Turbo",
            "llm_engine": "Groq Qwen 3.8 27B",
            "tts_engine": "Edge TTS · 4 音色",
            "server_status": "healthy"
        },
        "feeds": feeds_grouped,
        "active_tasks": active,
        "recent_completed": ready[:20],
        "failed_tasks": failed[:10]
    }

# ---------------- Pipeline Console (转储主页增强) ----------------

_QUEUE_STATUSES = ["pending", "transcribing", "translating", "synthesizing"]


def _pipeline_card(ep: Dict[str, Any], feed_map: Dict[str, Any], now: int) -> Dict[str, Any]:
    meta = feed_map.get(ep.get("feed_id", ""), {})
    updated = ep.get("updated_at") or now
    started = ep.get("dump_started_at") or 0
    # Historical rows carry no real dump start; report 0 rather than a fake duration.
    elapsed = (updated - started) if started > 0 and updated >= started else 0
    return {
        "episode_id": ep.get("id"),
        "title": ep.get("title", ""),
        "feed_id": ep.get("feed_id", ""),
        "feed_title": meta.get("title", "未知播客"),
        "cover_url": meta.get("cover_url", ""),
        "status": ep.get("status", "idle"),
        "progress": ep.get("progress", 0),
        "error_message": ep.get("error_message") or "",
        "elapsed_sec": elapsed,
        "updated_at": updated,
    }


@app.get("/api/v1/pipeline/queue")
def get_pipeline_queue(token: str = Depends(verify_token)):
    """Structured task queue for the dump console: running / queued / failed / completed."""
    feed_map = {f["id"]: f for f in db.list_feeds()}
    now = int(time.time())

    # Query by status directly — pagination-ordered list_episodes can hide
    # failed tasks that sit outside the newest-N window.
    running_eps = db.list_episodes_by_statuses(["transcribing", "translating", "synthesizing"], 200)
    queued_eps = db.list_episodes_by_statuses(["pending"], 200)
    failed_eps = db.list_episodes_by_statuses(["failed"], 200)
    completed_eps = db.list_episodes_by_statuses(["ready"], 200)

    running = [_pipeline_card(e, feed_map, now) for e in running_eps]
    queued = [_pipeline_card(e, feed_map, now) for e in queued_eps]
    failed = [_pipeline_card(e, feed_map, now) for e in failed_eps]
    completed = [_pipeline_card(e, feed_map, now) for e in completed_eps]

    return {
        "running": running,
        "queued": queued,
        "failed": failed,
        "completed": completed,
        "counts": {
            "running": len(running),
            "queued": len(queued),
            "failed": len(failed),
            "completed": len(completed),
        },
    }


@app.get("/api/v1/pipeline/stats")
def get_pipeline_stats(token: str = Depends(verify_token)):
    """Aggregate metrics: today's dumps, average duration, success rate, 7-day trend."""
    eps = db.list_episodes(limit=2000)
    now = int(time.time())
    today_start = int(time.mktime(time.strptime(time.strftime("%Y-%m-%d"), "%Y-%m-%d")))

    ready = [e for e in eps if e.get("status") == "ready"]
    failed = [e for e in eps if e.get("status") == "failed"]

    durations = [
        (e.get("updated_at") or 0) - (e.get("dump_started_at") or 0)
        for e in ready
        if (e.get("updated_at") or 0) > (e.get("dump_started_at") or 0) > 0
    ]
    avg_duration = int(sum(durations) / len(durations)) if durations else 0

    today_dumped = sum(1 for e in ready if (e.get("updated_at") or 0) >= today_start)
    finished = len(ready) + len(failed)
    success_rate = round(len(ready) / finished, 3) if finished else 1.0

    trend = []
    for i in range(6, -1, -1):
        day_key = time.strftime("%Y-%m-%d", time.localtime(now - i * 86400))
        start = int(time.mktime(time.strptime(day_key, "%Y-%m-%d")))
        end = start + 86400
        trend.append({
            "date": day_key,
            "count": sum(1 for e in ready if start <= (e.get("updated_at") or 0) < end),
        })

    return {
        "today_dumped": today_dumped,
        "avg_duration_sec": avg_duration,
        "success_rate": success_rate,
        "total_ready": len(ready),
        "total_failed": len(failed),
        "trend": trend,
    }


@app.get("/api/v1/settings")
def get_settings(token: str = Depends(verify_token)):
    """Pipeline settings: declared defaults merged with the user's overrides."""
    merged = dict(DEFAULT_SETTINGS)
    merged.update(db.get_settings())
    return {"settings": merged}


@app.put("/api/v1/settings")
def update_settings(payload: Dict[str, Any], token: str = Depends(verify_token)):
    """Update user-tunable pipeline settings.

    Unknown keys are rejected outright — a typo must fail loudly rather than
    silently persist a value nothing reads.
    """
    unknown = sorted(set(payload) - set(DEFAULT_SETTINGS))
    if unknown:
        raise HTTPException(status_code=400, detail=f"Unknown setting keys: {unknown}")
    merged = dict(DEFAULT_SETTINGS)
    merged.update(db.set_settings(payload))
    return {"settings": merged}


@app.post("/api/v1/pipeline/poll")
async def trigger_poll(token: str = Depends(verify_token)):
    """Run one feed poll cycle immediately (the same path the background loop uses)."""
    new_ids = await _poll_all_feeds()
    return {"new_episodes": len(new_ids), "episode_ids": new_ids}


@app.post("/api/v1/pipeline/batch-translate")
async def batch_translate(
    bg_tasks: BackgroundTasks,
    payload: Dict[str, Any],
    token: str = Depends(verify_token),
):
    """Queue many episodes at once. Pass episode_ids, or feed_id to sweep a podcast."""
    episode_ids = payload.get("episode_ids") or []
    feed_id = payload.get("feed_id")
    only_idle = bool(payload.get("only_idle", True))

    if feed_id:
        eps = db.list_episodes(feed_id=feed_id, limit=1000)
        wanted = ("idle",) if only_idle else ("idle", "failed")
        targets = [e["id"] for e in eps if e.get("status") in wanted]
    else:
        targets = list(episode_ids)

    queued, skipped = 0, 0
    for eid in targets:
        ep = db.get_episode(eid)
        if not ep or ep.get("status") in _QUEUE_STATUSES or ep.get("status") == "ready":
            skipped += 1
            continue
        db.update_episode_status(eid, status="pending", progress=0)
        bg_tasks.add_task(run_pipeline_task, eid)
        queued += 1

    return {
        "queued": queued,
        "skipped": skipped,
        "total_requested": len(targets),
    }


@app.post("/api/v1/episodes/{episode_id}/cancel")
def cancel_episode_translation(episode_id: str, token: str = Depends(verify_token)):
    """Cancel an in-flight pipeline task (resets DB state)."""
    ep = db.get_episode(episode_id)
    if not ep:
        raise HTTPException(status_code=404, detail="Episode not found")
    if ep["status"] not in _QUEUE_STATUSES:
        return {"status": ep["status"], "episode_id": episode_id, "message": "Task is not running"}
    db.update_episode_status(episode_id, status="idle", progress=0)
    return {"status": "idle", "episode_id": episode_id, "message": "Task cancelled"}


@app.delete("/api/v1/episodes/{episode_id}/artifacts")
def delete_episode_artifacts(episode_id: str, token: str = Depends(verify_token)):
    """Delete archived artifacts for an episode and reset it to idle."""
    ep = db.get_episode(episode_id)
    if not ep:
        raise HTTPException(status_code=404, detail="Episode not found")

    import shutil
    removed = False
    for base in (DATA_DIR / "archive", GDRIVE_DIR / "episodes"):
        target = base / episode_id
        if target.exists():
            shutil.rmtree(target, ignore_errors=True)
            removed = True

    db.update_episode_status(episode_id, status="idle", progress=0)
    return {"status": "idle", "episode_id": episode_id, "artifacts_removed": removed}


@app.get("/api/v1/episodes/{episode_id}/artifacts")
def get_episode_artifacts(episode_id: str, token: str = Depends(verify_token)):
    """Fetch all alignment JSONs, chapters, notes, and audio streaming info."""
    ep = db.get_episode(episode_id)
    if not ep:
        raise HTTPException(status_code=404, detail="Episode not found")

    # Locate archive directory: Prefer fast local SSD storage first (sub-millisecond)
    archive_dir = DATA_DIR / "archive" / episode_id
    if not archive_dir.exists():
        archive_dir = GDRIVE_DIR / "episodes" / episode_id

    timing_sync = []
    full_mapping = []
    chapters = []
    article_md = ""

    if (archive_dir / "timing_sync.json").exists():
        import json
        with open(archive_dir / "timing_sync.json", "r", encoding="utf-8") as f:
            timing_sync = json.load(f)

    if (archive_dir / "full_mapping.json").exists():
        import json
        with open(archive_dir / "full_mapping.json", "r", encoding="utf-8") as f:
            full_mapping = json.load(f)

    if (archive_dir / "chapters.json").exists():
        import json
        with open(archive_dir / "chapters.json", "r", encoding="utf-8") as f:
            chapters = json.load(f)

    if (archive_dir / "article.md").exists():
        with open(archive_dir / "article.md", "r", encoding="utf-8") as f:
            article_md = f.read()

    stream_info = archiver.get_google_stream_info(episode_id)

    return {
        "episode_id": episode_id,
        "status": ep["status"],
        "timing_sync": timing_sync,
        "full_mapping": full_mapping,
        "chapters": chapters,
        "article_markdown": article_md,
        "streaming": stream_info
    }

@app.post("/api/v1/ci/deploy")
async def ci_deploy_webhook(bg_tasks: BackgroundTasks, payload: Optional[Dict[str, Any]] = None):
    """Webhook triggered by GitHub Actions when iOS build succeeds: auto download, zsign, and publish to AirStore."""
    # The exact run id matters: `gh run download` without one resolves to the
    # newest run, which races the artifact index and can fetch the PREVIOUS
    # build (version bump silently not applied).
    run_id = str((payload or {}).get("run_id") or "").strip()

    def run_deploy():
        import subprocess, json, os, glob, shutil
        from pathlib import Path
        from datetime import datetime
        try:
            logger.info(f"Starting automated AirStore deployment (run_id={run_id or 'latest'})...")
            tmp_dir = "/tmp/airstore_ci_auto"
            shutil.rmtree(tmp_dir, ignore_errors=True)
            os.makedirs(tmp_dir, exist_ok=True)
            # 1. Download the artifact for THIS run (fallback: newest).
            #    Right after a run completes the artifact index can lag a few
            #    seconds; a single failed download used to abort the deploy.
            if run_id:
                dl_cmd = ["gh", "run", "download", run_id, "--name", "AmberPodcast-iOS-IPA",
                          "--dir", tmp_dir, "--repo", "Li-Qifeng/amber-podcast"]
            else:
                dl_cmd = ["gh", "run", "download", "--name", "AmberPodcast-iOS-IPA",
                          "--dir", tmp_dir, "--repo", "Li-Qifeng/amber-podcast"]
            import time as _time
            dl_ok, dl_err = False, ""
            for attempt in range(3):
                proc = subprocess.run(dl_cmd, capture_output=True, text=True)
                if proc.returncode == 0:
                    dl_ok = True
                    break
                dl_err = (proc.stderr or "").strip()[-400:]
                logger.warning(f"Artifact download attempt {attempt + 1}/3 failed: {dl_err}")
                if attempt < 2:
                    _time.sleep(5 * (attempt + 1))
            if not dl_ok:
                logger.error(f"Artifact download failed after 3 attempts: {dl_err}")
                return
            ipas = glob.glob(f"{tmp_dir}/*.ipa")
            if not ipas:
                logger.error("No IPA found in downloaded artifact")
                return
            src_ipa = ipas[0]

            # 1b. Verify the downloaded IPA really matches project.yml, otherwise
            # deploying it would publish a stale version under the new number.
            expected_ver = expected_build = None
            try:
                proj = Path("/root/projects/amber-podcast/ios/project.yml").read_text(encoding="utf-8")
                import re as _re
                mv = _re.search(r'MARKETING_VERSION:\s*["\']?([^"\'\s]+)', proj)
                cb = _re.search(r'CURRENT_PROJECT_VERSION:\s*["\']?([^"\'\s]+)', proj)
                expected_ver = mv.group(1) if mv else None
                expected_build = cb.group(1) if cb else None
            except Exception as _e:
                logger.warning(f"Could not read expected version: {_e}")

            if expected_ver:
                import zipfile, plistlib
                actual_ver = actual_build = None
                with zipfile.ZipFile(src_ipa) as zf:
                    for name in zf.namelist():
                        if name.endswith(".app/Info.plist"):
                            with zf.open(name) as fp:
                                info = plistlib.load(fp)
                            actual_ver = info.get("CFBundleShortVersionString")
                            actual_build = info.get("CFBundleVersion")
                            break
                if actual_ver != expected_ver:
                    logger.error(
                        f"Artifact version mismatch: ipa={actual_ver}({actual_build}) "
                        f"expected={expected_ver}({expected_build}); refusing to deploy stale build."
                    )
                    return
                logger.info(f"Version verified: {actual_ver} (build {actual_build}).")

            dist_ipa = "/root/projects/amber-podcast/dist/AmberPodcast.ipa"
            os.makedirs(os.path.dirname(dist_ipa), exist_ok=True)
            shutil.copy2(src_ipa, dist_ipa)

            # 2. Sign with zsign
            cert_pass = Path("/root/ios-re/airstore-pro/data/certs/default/pass.txt").read_text().strip()
            out_ipa = "/root/ios-re/airstore-pro/data/studio/amber-podcast/amber-podcast_signed.ipa"
            cmd = [
                "zsign",
                "-k", "/root/ios-re/airstore-pro/data/certs/default/cert.p12",
                "-p", cert_pass,
                "-m", "/root/ios-re/airstore-pro/data/certs/default/dev.mobileprovision",
                "-b", "com.ioslgm.46542",
                "-n", "Amber 播客",
                "-P", "-z", "1",
                "-o", out_ipa,
                dist_ipa
            ]
            subprocess.run(cmd, check=True)

            # 3. Read version from project.yml
            version = "2.7.2"
            try:
                import re
                txt = Path("/root/projects/amber-podcast/ios/project.yml").read_text()
                m = re.search(r'MARKETING_VERSION:\s*["\']?([^"\'\s]+)', txt)
                if m: version = m.group(1)
            except Exception: pass

            # 4. Update projects.json
            p_json = "/root/ios-re/airstore-pro/data/studio/projects.json"
            if os.path.exists(p_json):
                d = json.load(open(p_json))
                sz = round(os.path.getsize(out_ipa) / (1024 * 1024), 2)
                for item in d:
                    if item.get("id") == "amber-podcast":
                        item["version"] = version
                        item["size_mb"] = sz
                        item["updated_at"] = datetime.now().strftime("%m-%d %H:%M")
                json.dump(d, open(p_json, "w"), ensure_ascii=False, indent=2)

            logger.info(f"Automated AirStore deployment succeeded for Amber Podcast v{version}!")

            # 5. Notify user in Discord thread via Hermes CLI
            try:
                hermes_bin = "/usr/local/bin/hermes" if os.path.exists("/usr/local/bin/hermes") else "hermes"
                # 动态读取最近提交作为更新说明，避免硬编码过时内容
                try:
                    recent = subprocess.run(
                        ["git", "-C", "/root/projects/amber-podcast", "log", "--oneline", "-6"],
                        capture_output=True, text=True, timeout=10
                    ).stdout.strip()
                except Exception:
                    recent = "（更新说明获取失败，请查看 AirStore）"
                notify_msg = (
                    f"🚀 **Amber 播客 v{version} 已上架 AirStore Pro**\n\n"
                    f"- 状态: 自动签名并部署成功\n"
                    f"- 交付: `amber-podcast_signed.ipa` ({sz} MB)\n"
                    f"- 最近提交:\n```\n{recent}\n```"
                )
                subprocess.run([
                    hermes_bin, "send",
                    "--to", "discord:1506792208802513046:1558541255569440830",
                    notify_msg
                ], capture_output=True, text=True, timeout=15)
            except Exception as notify_err:
                logger.warning(f"Failed to send Discord notification: {notify_err}")
        except Exception as e:
            logger.error(f"Automated AirStore deployment failed: {e}")

    bg_tasks.add_task(run_deploy)
    return {"status": "ok", "message": "Deployment pipeline initiated"}

@app.get("/api/v1/episodes/{episode_id}/stream/{track}")
def stream_audio(episode_id: str, track: str = "chinese"):
    """Stream audio with HTTP Range support for native iOS AVPlayer seeking."""
    # Whitelist path components before touching the filesystem. AVPlayer loads
    # this URL without auth headers, so never add Depends(verify_token) here.
    if not re.fullmatch(r"[A-Za-z0-9_\-]+", episode_id):
        raise HTTPException(status_code=400, detail="Invalid episode id")
    if track not in ("chinese", "original"):
        raise HTTPException(status_code=400, detail="Invalid audio track")

    # Original downloads keep their source container (.mp3 in practice); only
    # the synthesized Chinese track is always .m4a. Never assume a fixed name.
    track_files = {
        "chinese": ["chinese_audio.m4a", "chinese.m4a"],
        "original": ["original_audio.m4a", "original.m4a", "original.mp3"],
    }
    candidates = track_files[track]
    search_dirs = [
        DATA_DIR / "archive" / episode_id,
        GDRIVE_DIR / "episodes" / episode_id,
        SCRATCH_DIR / episode_id,
    ]

    audio_file = None
    for directory in search_dirs:
        for name in candidates:
            candidate = directory / name
            if candidate.is_file() and candidate.stat().st_size > 0:
                audio_file = candidate
                break
        if audio_file is not None:
            break

    if audio_file is None:
        raise HTTPException(status_code=404, detail=f"Audio track '{track}' not found for episode")

    suffix = audio_file.suffix
    return FileResponse(
        path=str(audio_file),
        media_type="audio/mpeg" if suffix == ".mp3" else "audio/mp4",
        filename=f"{episode_id}_{track}{suffix}"
    )

# --- Playback Progress Sync ---

@app.post("/api/v1/playback/progress")
def update_playback_progress(
    req: ProgressUpdateRequest,
    token: str = Depends(verify_token)
):
    """Update listening progress and track mode."""
    db.update_playback_progress(
        episode_id=req.episode_id,
        position_ms=req.position_ms,
        duration_ms=req.duration_ms,
        track_mode=req.track_mode,
        is_finished=1 if req.is_finished else 0
    )
    return {"success": True, "progress": db.get_playback_progress(req.episode_id)}

@app.get("/api/v1/playback/progress/{episode_id}")
def get_playback_progress(episode_id: str, token: str = Depends(verify_token)):
    """Get listening progress for an episode."""
    prog = db.get_playback_progress(episode_id)
    return {"episode_id": episode_id, "playback_progress": prog}

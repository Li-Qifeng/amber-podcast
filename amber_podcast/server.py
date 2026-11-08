import os
import asyncio
import logging
import time
from typing import Optional, List, Dict, Any
from pathlib import Path
from fastapi import FastAPI, Depends, HTTPException, Header, Query, BackgroundTasks, status
from fastapi.responses import JSONResponse, FileResponse, StreamingResponse, RedirectResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

logger = logging.getLogger("amber_podcast")

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

app = FastAPI(title="Amber Podcast API", version="0.1.0")

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
                auto_translate=1 if req.auto_translate else 0
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
                auto_translate=1 if req.auto_translate else 0
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
        feed_id = f"feed_rss_{abs(hash(url)) % 100000000:08d}"
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

@app.get("/api/v1/library")
def get_library(token: str = Depends(verify_token)):
    """Fetch all subscribed podcasts and their latest 30 episodes in 1 single fast database call."""
    feeds = db.list_feeds()
    recent_episodes = db.list_episodes(feed_id=None, limit=30)
    return {
        "feeds": feeds,
        "recent_episodes": recent_episodes
    }

@app.api_route("/api/v1/images/proxy", methods=["GET", "HEAD"])
async def proxy_image(url: str = Query(...)):
    """Proxy, compress, and cache external podcast cover images (resolving CDN timeouts and mobile network slowness)."""
    clean_url = url.strip()
    if not clean_url:
        raise HTTPException(status_code=400, detail="Missing url")

    cache_dir = SCRATCH_DIR / "images"
    cache_dir.mkdir(parents=True, exist_ok=True)

    import hashlib
    url_hash = hashlib.md5(clean_url.encode("utf-8")).hexdigest()
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
                img = Image.new("RGB", (500, 500), color="#18181b")
                draw = ImageDraw.Draw(img)
                heights = [30, 60, 95, 140, 180, 210, 190, 150, 110, 70, 45, 25]
                for i, h in enumerate(heights):
                    x = 110 + i * 24
                    draw.rounded_rectangle([x, 250 - h//2, x + 12, 250 + h//2], radius=6, fill="#d4a373")
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
                    img.thumbnail((500, 500), Image.Resampling.LANCZOS)
                    img.convert("RGB").save(str(cached_file), "JPEG", quality=82, optimize=True)
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
    
    feed_id = f"preview_{abs(hash(clean_url)) % 100000000:08d}"
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

        # Step 2: ASR Transcription
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
    token: str = Depends(verify_token)
):
    """Trigger background dual-track AI translation for an episode."""
    ep = db.get_episode(episode_id)
    if not ep:
        raise HTTPException(status_code=404, detail="Episode not found")

    if ep["status"] in ["transcribing", "translating", "synthesizing"]:
        return {"status": ep["status"], "progress": ep["progress"], "message": "Translation already in progress"}

    db.update_episode_status(episode_id, status="pending", progress=0)
    bg_tasks.add_task(run_pipeline_task, episode_id)
    return {"status": "pending", "episode_id": episode_id, "message": "Translation task queued"}

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
async def ci_deploy_webhook(bg_tasks: BackgroundTasks, token: str = Depends(verify_token)):
    """Webhook triggered by GitHub Actions when iOS build succeeds: auto download, zsign, and publish to AirStore."""
    def run_deploy():
        import subprocess, json, os, glob, shutil
        from pathlib import Path
        from datetime import datetime
        try:
            logger.info("Starting automated AirStore deployment from GitHub Actions...")
            tmp_dir = "/tmp/airstore_ci_auto"
            shutil.rmtree(tmp_dir, ignore_errors=True)
            os.makedirs(tmp_dir, exist_ok=True)
            # 1. Download latest artifact
            subprocess.run(["gh", "run", "download", "--name", "AmberPodcast-iOS-IPA", "--dir", tmp_dir, "--repo", "Li-Qifeng/amber-podcast"], check=True)
            ipas = glob.glob(f"{tmp_dir}/*.ipa")
            if not ipas:
                logger.error("No IPA found in downloaded artifact")
                return
            src_ipa = ipas[0]
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
        except Exception as e:
            logger.error(f"Automated AirStore deployment failed: {e}")

    bg_tasks.add_task(run_deploy)
    return {"status": "ok", "message": "Deployment pipeline initiated"}

@app.get("/api/v1/episodes/{episode_id}/stream/{track}")
def stream_audio(episode_id: str, track: str = "chinese"):
    """Stream audio with HTTP Range support for native iOS AVPlayer seeking."""
    archive_dir = DATA_DIR / "archive" / episode_id
    if not archive_dir.exists():
        archive_dir = GDRIVE_DIR / "episodes" / episode_id

    audio_file = archive_dir / f"{track}_audio.m4a"
    if not audio_file.exists():
        # Fallback to scratch directory
        scratch_file = SCRATCH_DIR / episode_id / f"{track}_audio.m4a"
        if scratch_file.exists():
            audio_file = scratch_file
        else:
            raise HTTPException(status_code=404, detail=f"Audio track '{track}' not found for episode")

    return FileResponse(
        path=str(audio_file),
        media_type="audio/mp4",
        filename=f"{episode_id}_{track}.m4a"
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

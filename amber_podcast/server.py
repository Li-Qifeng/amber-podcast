import os
import asyncio
import logging
from typing import Optional, List, Dict, Any
from pathlib import Path
from fastapi import FastAPI, Depends, HTTPException, Header, Query, BackgroundTasks, status
from fastapi.responses import JSONResponse, FileResponse, StreamingResponse
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

@app.get("/api/v1/discover")
def get_discover_feed(token: str = Depends(verify_token)):
    """Curated Apple Podcasts-style discovery feed with featured carousels, top Chinese/global charts."""
    return {
        "featured": [
            {
                "id": "discover_etw",
                "collection_id": "1183662640",
                "source_type": "apple_rss",
                "title": "声东击西",
                "author": "ETW Studio",
                "feed_url": "https://etw.fm/rss",
                "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/90/a6/5e/90a65e75-fa5e-b839-411a-1d70a323a74a/mza_11979956488732152435.jpg/600x600bb.jpg",
                "description": "带你看不一样的世界 · 深度跨文化对谈",
                "genre": "深度对谈",
                "editorial_tag": "本周精选 · 深度对话",
                "track_count": 435,
                "auto_translate": 0
            },
            {
                "id": "discover_huberman",
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
                "id": "discover_gcores",
                "collection_id": "420660752",
                "source_type": "apple_rss",
                "title": "机核游戏频道",
                "author": "机核网 www.gcores.com",
                "feed_url": "https://alioss.gcores.com/feeds/apple_podcast_v1.xml",
                "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/fb/c2/66/fbc26663-f3b2-37dc-0f3e-32430843d7e1/mza_11184489343271545713.png/600x600bb.jpg",
                "description": "游戏文化、泛流行文化与硬核玩家长篇对白",
                "genre": "文化生活",
                "editorial_tag": "中文标杆 · 先锋文化",
                "track_count": 1732,
                "auto_translate": 0
            },
            {
                "id": "discover_acquired",
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
        ],
        "top_chinese": [
            {
                "id": "discover_hzyy",
                "collection_id": "1493503146",
                "source_type": "apple_rss",
                "title": "忽左忽右",
                "author": "JustPod",
                "feed_url": "https://justpodmedia.com/rss/left-right.xml",
                "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/d9/33/c2/d933c2a3-2f22-5b9e-64c8-3e4b75a133df/mza_16489369902340578854.jpg/600x600bb.jpg",
                "description": "沙龙式的长篇人文对白，穿梭于历史、思想与现实之间",
                "genre": "社会人文",
                "track_count": 654,
                "auto_translate": 0
            },
            {
                "id": "discover_zxjg",
                "collection_id": "1559695855",
                "source_type": "apple_rss",
                "title": "知行小酒馆",
                "author": "有知有行",
                "feed_url": "https://feed.xyzfm.space/j8yp8gxkmgqr",
                "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts125/v4/80/e7/76/80e776ff-db8d-9da5-f2ad-8ecb7858c5cb/mza_17294285117904005073.jpg/600x600bb.jpg",
                "description": "关于金钱、工作与人生的温柔且清醒的对谈",
                "genre": "投资生活",
                "track_count": 180,
                "auto_translate": 0
            },
            {
                "id": "discover_tdfm",
                "collection_id": "1503310051",
                "source_type": "apple_rss",
                "title": "跳岛 FM",
                "author": "中信出版·大方",
                "feed_url": "https://feed.xyzfm.space/m41mpxeqw53q",
                "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts126/v4/3d/bf/bd/3dbfbd48-2b81-fa83-3635-442436f56195/mza_15502621008034509462.jpg/600x600bb.jpg",
                "description": "一份文学播客，在岛屿之间搭起思想的渡口",
                "genre": "文学艺术",
                "track_count": 210,
                "auto_translate": 0
            },
            {
                "id": "discover_sdyzk",
                "collection_id": "1573189055",
                "source_type": "apple_rss",
                "title": "声动早咖啡",
                "author": "声动活泼",
                "feed_url": "https://www.ximalaya.com/album/51076156.xml",
                "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts116/v4/28/70/46/28704618-9366-0dbb-d368-232ff492a5ee/mza_17282869502213791051.jpg/600x600bb.jpg",
                "description": "用 15 分钟为你的早晨充电，速览全球商业与科技动态",
                "genre": "商业资讯",
                "track_count": 780,
                "auto_translate": 0
            }
        ],
        "top_global": [
            {
                "id": "discover_lex",
                "collection_id": "1434243584",
                "source_type": "apple_rss",
                "title": "Lex Fridman Podcast",
                "author": "Lex Fridman",
                "feed_url": "https://lexfridman.com/feed/podcast/",
                "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts221/v4/2c/3d/62/2c3d623e-63f5-7e04-37a5-c7e6822262ea/mza_14389689408611956162.jpg/600x600bb.jpg",
                "description": "关于人工智能、前沿科学、意识哲学与人类命运的对话",
                "genre": "科技·AI",
                "track_count": 503,
                "auto_translate": 1
            },
            {
                "id": "discover_allin",
                "collection_id": "1507616474",
                "source_type": "apple_rss",
                "title": "All-In with Chamath, Jason, Sacks & Friedberg",
                "author": "All-In Podcast",
                "feed_url": "https://allin.libsyn.com/rss",
                "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts211/v4/05/2f/18/052f1837-7756-3a78-2900-5178652cba67/mza_17316130767576579375.jpg/600x600bb.jpg",
                "description": "硅谷四位风投巨头在经济、技术与地缘政治上的前沿博弈",
                "genre": "商业风投",
                "track_count": 215,
                "auto_translate": 1
            },
            {
                "id": "discover_hardfork",
                "collection_id": "1528594034",
                "source_type": "apple_rss",
                "title": "Hard Fork",
                "author": "The New York Times",
                "feed_url": "https://feeds.simplecast.com/l2i9YnTd",
                "cover_url": "https://is1-ssl.mzstatic.com/image/thumb/Podcasts122/v4/8e/31/54/8e3154f8-154a-a28a-7dcf-18e4e9089025/mza_13203494793547141528.jpg/600x600bb.jpg",
                "description": "《纽约时报》王牌科技播客，深入解剖硅谷与人工智能前线",
                "genre": "科技观察",
                "track_count": 160,
                "auto_translate": 1
            }
        ]
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
    """Proxy and cache external podcast cover images (resolving CDN timeouts and network unreachability)."""
    clean_url = url.strip()
    if not clean_url:
        raise HTTPException(status_code=400, detail="Missing url")

    cache_dir = SCRATCH_DIR / "images"
    cache_dir.mkdir(parents=True, exist_ok=True)

    import hashlib
    url_hash = hashlib.md5(clean_url.encode("utf-8")).hexdigest()
    cached_file = cache_dir / f"{url_hash}.jpg"

    if cached_file.exists() and cached_file.stat().st_size > 0:
        return FileResponse(str(cached_file), media_type="image/jpeg")

    import httpx
    from fastapi.responses import RedirectResponse
    try:
        async with httpx.AsyncClient(timeout=12.0, follow_redirects=True) as client:
            resp = await client.get(clean_url)
            if resp.status_code == 200:
                with open(cached_file, "wb") as f:
                    f.write(resp.content)
                media_type = resp.headers.get("content-type", "image/jpeg")
                return FileResponse(str(cached_file), media_type=media_type)
    except Exception as e:
        logger.warning(f"Image proxy failed for {clean_url}: {e}")

    return RedirectResponse(url=clean_url)

@app.delete("/api/v1/feeds/{feed_id}")
def delete_feed(feed_id: str, token: str = Depends(verify_token)):
    """Unsubscribe from a podcast feed."""
    success = db.delete_feed(feed_id)
    if not success:
        raise HTTPException(status_code=404, detail="Feed not found")
    return {"success": True, "feed_id": feed_id}

@app.get("/api/v1/feeds/{feed_id}/episodes")
def list_feed_episodes(
    feed_id: str,
    limit: int = 50,
    offset: int = 0,
    token: str = Depends(verify_token)
):
    """List episodes for a given feed."""
    episodes = db.list_episodes(feed_id=feed_id, limit=limit, offset=offset)
    return {"feed_id": feed_id, "episodes": episodes}

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

    # Locate archive directory
    archive_dir = GDRIVE_DIR / "episodes" / episode_id
    if not archive_dir.exists():
        archive_dir = DATA_DIR / "archive" / episode_id

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

# --- Audio Streaming with HTTP Range Support ---

@app.get("/api/v1/episodes/{episode_id}/stream/{track}")
def stream_audio(episode_id: str, track: str = "chinese"):
    """Stream audio with HTTP Range support for native iOS AVPlayer seeking."""
    archive_dir = GDRIVE_DIR / "episodes" / episode_id
    if not archive_dir.exists():
        archive_dir = DATA_DIR / "archive" / episode_id

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

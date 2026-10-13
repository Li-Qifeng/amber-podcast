import os
import asyncio
from typing import Optional, List, Dict, Any
from pathlib import Path
from fastapi import FastAPI, Depends, HTTPException, Header, Query, BackgroundTasks, status
from fastapi.responses import JSONResponse, FileResponse, StreamingResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

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

@app.get("/api/v1/search")
async def search_podcasts(
    q: str = Query(..., min_length=1),
    limit: int = 15,
    token: str = Depends(verify_token)
):
    """Search for podcasts across Apple Podcasts Directory."""
    results = await apple_agg.search_podcasts(query=q, limit=limit)
    return {"query": q, "results": results}

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

import pytest
from starlette.testclient import TestClient
from amber_podcast.server import app, db
from amber_podcast.config import AUTH_TOKEN

client = TestClient(app)

def test_health():
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert data["app"] == "amber-podcast"

def test_auth_rejection():
    # Missing auth
    resp = client.get("/api/v1/feeds")
    assert resp.status_code == 401

    # Invalid token
    resp = client.get("/api/v1/feeds", headers={"Authorization": "Bearer wrong-token"})
    assert resp.status_code == 401

def test_feed_and_episode_endpoints():
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}

    # 1. Manually insert feed in test DB
    feed_id = "feed_test_server"
    db.upsert_feed(
        feed_id=feed_id,
        source_type="apple_rss",
        title="Server Test Podcast",
        author="Jarvis",
        feed_url="https://example.com/rss",
        cover_url="https://example.com/cover.png",
        description="Testing endpoints"
    )

    # 2. List feeds
    resp = client.get("/api/v1/feeds", headers=headers)
    assert resp.status_code == 200
    feeds = resp.json()["feeds"]
    assert any(f["id"] == feed_id for f in feeds)

    # 3. Insert episode
    ep_id = "ep_test_server_01"
    db.upsert_episode(
        episode_id=ep_id,
        feed_id=feed_id,
        title="Test Episode 1",
        audio_url="https://example.com/audio.mp3",
        duration=1800,
        shownotes="Shownotes content 02:30 Topic A"
    )

    # 4. List episodes
    resp = client.get(f"/api/v1/feeds/{feed_id}/episodes", headers=headers)
    assert resp.status_code == 200
    episodes = resp.json()["episodes"]
    assert len(episodes) >= 1
    assert episodes[0]["id"] == ep_id

    # 5. Episode detail
    resp = client.get(f"/api/v1/episodes/{ep_id}", headers=headers)
    assert resp.status_code == 200
    assert resp.json()["episode"]["title"] == "Test Episode 1"

    # 6. Artifacts endpoint
    resp = client.get(f"/api/v1/episodes/{ep_id}/artifacts", headers=headers)
    assert resp.status_code == 200
    artifacts = resp.json()
    assert artifacts["episode_id"] == ep_id
    assert "streaming" in artifacts

    # 7. Playback progress sync
    progress_payload = {
        "episode_id": ep_id,
        "position_ms": 45000,
        "duration_ms": 1800000,
        "track_mode": "alternating",
        "is_finished": False
    }
    resp = client.post("/api/v1/playback/progress", headers=headers, json=progress_payload)
    assert resp.status_code == 200
    assert resp.json()["success"] is True

    # 8. Get progress
    resp = client.get(f"/api/v1/playback/progress/{ep_id}", headers=headers)
    assert resp.status_code == 200
    prog = resp.json()["playback_progress"]
    assert prog["position_ms"] == 45000
    assert prog["track_mode"] == "alternating"

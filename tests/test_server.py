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


def test_subscribe_invalid_url_returns_4xx():
    """Regression: a malformed feed URL must never leak a 500 + traceback."""
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    resp = client.post(
        "/api/v1/feeds/subscribe",
        json={"url": "not-a-valid-url"},
        headers=headers,
    )
    assert resp.status_code == 400, resp.text
    assert "无法订阅" in resp.json()["detail"]


def test_stream_original_track_resolves(tmp_path, monkeypatch):
    """Regression: the original track keeps its source container (.mp3)."""
    import amber_podcast.server as server_mod

    eid = "test_stream_original"
    scratch = tmp_path / "scratch" / eid
    scratch.mkdir(parents=True)
    (scratch / "original.mp3").write_bytes(b"ID3" + b"\x00" * 128)

    monkeypatch.setattr(server_mod, "DATA_DIR", tmp_path / "empty_data")
    monkeypatch.setattr(server_mod, "GDRIVE_DIR", tmp_path / "empty_gdrive")
    monkeypatch.setattr(server_mod, "SCRATCH_DIR", tmp_path / "scratch")

    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    resp = client.get(f"/api/v1/episodes/{eid}/stream/original", headers=headers)
    assert resp.status_code in (200, 206), resp.text
    assert resp.headers["content-type"].startswith("audio/mpeg")


def test_stream_rejects_invalid_episode_id_and_track():
    """Regression: path components must be whitelisted before filesystem access."""
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    bad_id = client.get("/api/v1/episodes/foo.bar/stream/chinese", headers=headers)
    assert bad_id.status_code == 400, bad_id.text
    bad_track = client.get("/api/v1/episodes/some_episode/stream/secret", headers=headers)
    assert bad_track.status_code == 400, bad_track.text


# --- hero_episode selection (P0: only post-subscribe publications reach the hero) ---

from amber_podcast.server import _pick_hero_episode


def _feed_row(fid, created_at):
    return {"id": fid, "created_at": created_at}


def _episode_row(eid, fid, pub_ts):
    return {"id": eid, "feed_id": fid, "pub_ts": pub_ts, "pub_date": ""}


def test_pick_hero_episode_only_after_subscribe():
    subscribed = 1_700_000_000
    feeds = [_feed_row("f1", subscribed)]
    episodes = [
        _episode_row("old", "f1", subscribed - 86400),
        _episode_row("new", "f1", subscribed + 3600),
    ]
    assert _pick_hero_episode(feeds, episodes)["id"] == "new"


def test_pick_hero_episode_none_when_backcatalogue_only():
    """A freshly subscribed show must not push its archive into the hero."""
    subscribed = 1_700_000_000
    feeds = [_feed_row("f1", subscribed)]
    episodes = [
        _episode_row("old1", "f1", subscribed - 86400),
        _episode_row("old2", "f1", subscribed - 7200),
    ]
    assert _pick_hero_episode(feeds, episodes) is None


def test_pick_hero_episode_picks_newest_across_feeds():
    feeds = [_feed_row("f1", 100), _feed_row("f2", 100)]
    episodes = [_episode_row("a", "f1", 200), _episode_row("b", "f2", 300)]
    assert _pick_hero_episode(feeds, episodes)["id"] == "b"


def test_list_episodes_sorts_by_pub_ts_not_lexicographic_text():
    """'Wed, 31 May 2023' sorts ABOVE 'Wed, 11 Nov 2026' as raw TEXT."""
    fid = "feed_pubts_sort"
    db.upsert_feed(feed_id=fid, source_type="apple_rss", title="PubTs",
                   author="T", feed_url="https://example.com/pubts",
                   cover_url="", description="")
    db.upsert_episode(episode_id="p_2023", feed_id=fid, title="2023",
                      audio_url="https://e/a.mp3",
                      pub_date="Wed, 31 May 2023 23:00:00 GMT")
    db.upsert_episode(episode_id="p_2026", feed_id=fid, title="2026",
                      audio_url="https://e/b.mp3",
                      pub_date="Wed, 11 Nov 2026 10:00:00 GMT")
    rows = db.list_episodes(feed_id=fid, limit=10)
    assert [r["id"] for r in rows][:2] == ["p_2026", "p_2023"]


def test_library_payload_exposes_hero_episode_field():
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    resp = client.get("/api/v1/library", headers=headers)
    assert resp.status_code == 200, resp.text
    assert "hero_episode" in resp.json()

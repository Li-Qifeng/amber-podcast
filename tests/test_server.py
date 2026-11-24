import pytest
from starlette.testclient import TestClient
from amber_podcast.server import app, db
from amber_podcast.config import AUTH_TOKEN

# Hard guard: the suite must never run against the production database.
# conftest.py injects AMBER_DB_PATH before amber_podcast is imported, but that
# isolation has silently failed at least twice (13:52 and 20:50 on 2026-11-12),
# writing straight into data/amber.db. If the path is not a throwaway test DB,
# abort the whole session instead of touching real data.
from amber_podcast.config import DB_PATH as _DB_PATH_UNDER_TEST

if "amber_test_" not in str(_DB_PATH_UNDER_TEST):
    pytest.exit(
        f"Refusing to run: DB_PATH={_DB_PATH_UNDER_TEST} is not an isolated test database. "
        "conftest.py isolation did not apply — refusing to touch production data.",
        returncode=1,
    )

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


# --- P1: feed polling + auto-transcription scoping ---

import asyncio
from email.utils import formatdate

import amber_podcast.server as server_mod


def test_queue_auto_translations_only_new_post_subscribe_episodes(monkeypatch):
    enqueued = []
    monkeypatch.setattr(server_mod, "_enqueue_pipeline", lambda eid: (enqueued.append(eid), True)[1])

    db.upsert_feed(feed_id="feed_p1_auto", source_type="apple_rss", title="Auto",
                   author="T", feed_url="https://example.com/p1-auto",
                   cover_url="", description="", auto_translate=1)
    feed = db.get_feed("feed_p1_auto")
    db.upsert_episode(episode_id="p1_new", feed_id="feed_p1_auto", title="new",
                      audio_url="https://e/n.mp3",
                      pub_date=formatdate(feed["created_at"] + 3600, usegmt=True))
    db.upsert_episode(episode_id="p1_old", feed_id="feed_p1_auto", title="old",
                      audio_url="https://e/o.mp3",
                      pub_date=formatdate(feed["created_at"] - 86400, usegmt=True))

    queued = server_mod._queue_auto_translations(["p1_new", "p1_old"])
    assert queued == 1
    assert enqueued == ["p1_new"]


def test_queue_auto_translations_skips_non_auto_translate_feeds(monkeypatch):
    enqueued = []
    monkeypatch.setattr(server_mod, "_enqueue_pipeline", lambda eid: (enqueued.append(eid), True)[1])

    db.upsert_feed(feed_id="feed_p1_manual", source_type="apple_rss", title="Manual",
                   author="T", feed_url="https://example.com/p1-manual",
                   cover_url="", description="", auto_translate=0)
    feed = db.get_feed("feed_p1_manual")
    db.upsert_episode(episode_id="p1_manual_new", feed_id="feed_p1_manual", title="new",
                      audio_url="https://e/m.mp3",
                      pub_date=formatdate(feed["created_at"] + 3600, usegmt=True))

    assert server_mod._queue_auto_translations(["p1_manual_new"]) == 0
    assert enqueued == []


def test_queue_auto_translations_skips_non_idle(monkeypatch):
    enqueued = []
    monkeypatch.setattr(server_mod, "_enqueue_pipeline", lambda eid: (enqueued.append(eid), True)[1])

    db.upsert_feed(feed_id="feed_p1_busy", source_type="apple_rss", title="Busy",
                   author="T", feed_url="https://example.com/p1-busy",
                   cover_url="", description="", auto_translate=1)
    feed = db.get_feed("feed_p1_busy")
    db.upsert_episode(episode_id="p1_busy", feed_id="feed_p1_busy", title="busy",
                      audio_url="https://e/b.mp3",
                      pub_date=formatdate(feed["created_at"] + 3600, usegmt=True))
    db.update_episode_status("p1_busy", status="transcribing")

    assert server_mod._queue_auto_translations(["p1_busy"]) == 0
    assert enqueued == []


def test_poll_all_feeds_reports_episode_only_once(monkeypatch):
    """Second poll cycle must not report the same episode as new."""
    db.upsert_feed(feed_id="feed_p1_poll", source_type="apple_rss", title="Poll",
                   author="T", feed_url="https://example.com/p1-poll",
                   cover_url="", description="", auto_translate=0)

    payload = {
        "feed": {"title": "Poll", "author": "T", "cover_url": "", "description": ""},
        "episodes": [{
            "id": "poll_ep_1", "title": "Ep1", "audio_url": "https://e/1.mp3",
            "duration": 60, "pub_date": "Wed, 11 Nov 2026 10:00:00 GMT",
            "shownotes": "", "guid": "g1",
        }],
    }

    async def fake_fetch(url, feed_id):
        return payload if feed_id == "feed_p1_poll" else {"episodes": []}

    monkeypatch.setattr(server_mod.apple_agg, "fetch_and_parse_feed", fake_fetch)
    monkeypatch.setattr(server_mod, "_enqueue_pipeline", lambda eid: None)

    first = asyncio.run(server_mod._poll_all_feeds())
    assert "poll_ep_1" in first
    second = asyncio.run(server_mod._poll_all_feeds())
    assert second == []


def test_poll_endpoint_requires_auth():
    resp = client.post("/api/v1/pipeline/poll")
    assert resp.status_code == 401


# --- P1: tunable pipeline settings ---

def test_settings_defaults_and_update():
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    resp = client.get("/api/v1/settings", headers=headers)
    assert resp.status_code == 200, resp.text
    settings = resp.json()["settings"]
    assert set(settings) == {"auto_translate_default", "poll_interval_sec", "max_concurrent_pipelines"}

    resp = client.put("/api/v1/settings", headers=headers, json={"poll_interval_sec": 900})
    assert resp.status_code == 200, resp.text
    assert resp.json()["settings"]["poll_interval_sec"] == "900"

    again = client.get("/api/v1/settings", headers=headers).json()["settings"]
    assert again["poll_interval_sec"] == "900"


def test_settings_rejects_unknown_keys():
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    resp = client.put("/api/v1/settings", headers=headers, json={"nonsense": 1})
    assert resp.status_code == 400, resp.text


def test_settings_requires_auth():
    assert client.get("/api/v1/settings").status_code == 401


def test_enqueue_pipeline_respects_concurrency_cap():
    db.upsert_feed(feed_id="feed_cap", source_type="apple_rss", title="Cap",
                   author="T", feed_url="https://example.com/cap",
                   cover_url="", description="")
    db.upsert_episode(episode_id="cap_running", feed_id="feed_cap", title="running",
                      audio_url="https://e/r.mp3",
                      pub_date="Wed, 11 Nov 2026 10:00:00 GMT")
    db.update_episode_status("cap_running", status="transcribing")

    # default cap is 1 and one pipeline is already active -> refuse
    assert server_mod._enqueue_pipeline("cap_new") is False


def test_set_feed_auto_translate_endpoint():
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    db.upsert_feed(feed_id="feed_policy", source_type="apple_rss", title="Policy",
                   author="T", feed_url="https://example.com/policy",
                   cover_url="", description="", auto_translate=0)
    r = client.put("/api/v1/feeds/feed_policy/auto-translate", json={"enabled": True}, headers=headers)
    assert r.status_code == 200
    assert r.json()["auto_translate"] == 1
    assert db.get_feed("feed_policy")["auto_translate"] == 1
    r2 = client.put("/api/v1/feeds/feed_policy/auto-translate", json={"enabled": False}, headers=headers)
    assert r2.json()["auto_translate"] == 0
    assert db.get_feed("feed_policy")["auto_translate"] == 0
    r3 = client.put("/api/v1/feeds/feed_missing/auto-translate", json={"enabled": True}, headers=headers)
    assert r3.status_code == 404


def test_cancel_all_resets_queue_to_idle():
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    db.upsert_feed(feed_id="feed_cancelall", source_type="apple_rss", title="CA",
                   author="T", feed_url="https://example.com/cancelall",
                   cover_url="", description="")
    for eid, st in [("ca_pending", "pending"), ("ca_running", "transcribing")]:
        db.upsert_episode(episode_id=eid, feed_id="feed_cancelall", title=eid,
                          audio_url="https://e/x.mp3", pub_date="Wed, 11 Nov 2026 10:00:00 GMT")
        db.update_episode_status(eid, status=st)
    r = client.post("/api/v1/pipeline/cancel-all", headers=headers)
    assert r.status_code == 200
    assert r.json()["cancelled"] >= 2
    assert db.get_episode("ca_pending")["status"] == "idle"
    assert db.get_episode("ca_running")["status"] == "idle"
    assert "ca_running" in server_mod._cancelled_episodes


def test_batch_translate_marks_pending_without_immediate_launch(monkeypatch):
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    launched = []
    monkeypatch.setattr(server_mod, "run_pipeline_task", lambda eid: launched.append(eid))
    db.upsert_feed(feed_id="feed_batch", source_type="apple_rss", title="Batch",
                   author="T", feed_url="https://example.com/batch",
                   cover_url="", description="")
    for i in range(3):
        db.upsert_episode(episode_id=f"batch_{i}", feed_id="feed_batch", title=f"b{i}",
                          audio_url="https://e/b.mp3", pub_date="Wed, 11 Nov 2026 10:00:00 GMT")
    r = client.post("/api/v1/pipeline/batch-translate",
                    json={"feed_id": "feed_batch", "only_idle": True}, headers=headers)
    assert r.status_code == 200
    assert r.json()["queued"] == 3
    # batch must NOT launch tasks directly; the capped scheduler drains pending
    assert launched == []
    for i in range(3):
        assert db.get_episode(f"batch_{i}")["status"] == "pending"


def test_abort_if_cancelled_restores_idle():
    db.upsert_feed(feed_id="feed_abort", source_type="apple_rss", title="Abort",
                   author="T", feed_url="https://example.com/abort",
                   cover_url="", description="")
    db.upsert_episode(episode_id="abort_ep", feed_id="feed_abort", title="a",
                      audio_url="https://e/a.mp3", pub_date="Wed, 11 Nov 2026 10:00:00 GMT")
    db.update_episode_status("abort_ep", status="transcribing")
    server_mod._cancelled_episodes.add("abort_ep")
    assert server_mod._abort_if_cancelled("abort_ep") is True
    assert db.get_episode("abort_ep")["status"] == "idle"
    assert "abort_ep" not in server_mod._cancelled_episodes
    assert server_mod._abort_if_cancelled("abort_ep") is False


def test_pipeline_status_exposes_per_feed_auto_translate():
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    db.upsert_feed(feed_id="feed_status_at", source_type="apple_rss", title="StatusAT",
                   author="T", feed_url="https://example.com/status-at",
                   cover_url="", description="", auto_translate=1)
    db.upsert_episode(episode_id="status_at_ep", feed_id="feed_status_at", title="e",
                      audio_url="https://e/s.mp3", pub_date="Wed, 11 Nov 2026 10:00:00 GMT")
    r = client.get("/api/v1/pipeline/status", headers=headers)
    assert r.status_code == 200
    grp = [g for g in r.json()["feeds"] if g["feed_id"] == "feed_status_at"][0]
    assert grp["auto_translate"] == 1


def test_rss_subscribe_respects_auto_translate_default(monkeypatch):
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}

    async def fake_fetch(feed_url, feed_id):
        return {"feed": {"title": "RSS Default", "author": "A", "cover_url": "", "description": ""},
                "episodes": []}

    monkeypatch.setattr(server_mod.apple_agg, "fetch_and_parse_feed", fake_fetch)
    try:
        client.put("/api/v1/settings", json={"auto_translate_default": "0"}, headers=headers)
        r = client.post("/api/v1/feeds/subscribe",
                        json={"url": "https://example.com/rss-default-off", "auto_translate": False},
                        headers=headers)
        assert r.status_code == 200
        f = db.get_feed(r.json()["feed"]["id"])
        assert f is not None and f["auto_translate"] == 0

        client.put("/api/v1/settings", json={"auto_translate_default": "1"}, headers=headers)
        r2 = client.post("/api/v1/feeds/subscribe",
                         json={"url": "https://example.com/rss-default-on", "auto_translate": False},
                         headers=headers)
        assert r2.status_code == 200
        f2 = db.get_feed(r2.json()["feed"]["id"])
        assert f2 is not None and f2["auto_translate"] == 1
    finally:
        client.put("/api/v1/settings", json={"auto_translate_default": "0"}, headers=headers)



def test_health_reports_real_app_version():
    """/health must expose the shipped iOS version from ios/project.yml, not a hardcoded 0.1.0."""
    import re
    from pathlib import Path
    from starlette.testclient import TestClient
    from amber_podcast.server import app
    proj = (Path(__file__).resolve().parent.parent / "ios" / "project.yml").read_text()
    mv = re.search(r'MARKETING_VERSION:\s*["\']?([^"\'\s]+)', proj).group(1)
    cb = re.search(r'CURRENT_PROJECT_VERSION:\s*["\']?([^"\'\s]+)', proj).group(1)
    body = TestClient(app).get("/health").json()
    assert body["status"] == "ok"
    assert body["version"] == mv
    assert body["build"] == cb


# --- discover: 50-item shelves + latest_episode spotlight ---


def _fake_shelf_items(count: int) -> list:
    return [
        {
            "id": str(900000 + i),
            "collection_id": str(900000 + i),
            "source_type": "apple_rss",
            "title": f"Shelf Show {i}",
            "author": "A",
            "feed_url": f"https://example.com/shelf-{i}",
            "cover_url": "",
            "description": "",
            "genre": "科技",
            "track_count": 0,
            "auto_translate": 0,
        }
        for i in range(count)
    ]


def _patch_discover(monkeypatch, shelf_items, latest_impl):
    async def fake_top(country, limit=20):
        return []  # empty -> curated fallback lists, no network

    async def fake_genre(country, gid, limit=20):
        return list(shelf_items)

    monkeypatch.setattr(server_mod.apple_agg, "fetch_top_podcasts", fake_top)
    monkeypatch.setattr(server_mod.apple_agg, "fetch_top_by_genre", fake_genre)
    monkeypatch.setattr(server_mod.apple_agg, "fetch_latest_episode", latest_impl)


def test_discover_categories_return_50_items_with_latest_episode(monkeypatch):
    async def fake_latest(feed_url, feed_id):
        return {
            "id": f"{feed_id}_ep1",
            "title": "Latest Ep",
            "duration": 1234,
            "pub_date": "Thu, 12 Nov 2026 10:00:00 GMT",
            "audio_url": "https://e/latest.mp3",
        }

    _patch_discover(monkeypatch, _fake_shelf_items(50), fake_latest)
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    resp = client.get("/api/v1/discover", headers=headers)
    assert resp.status_code == 200, resp.text
    data = resp.json()
    # Contract unchanged: same top-level keys (additions only).
    assert set(data) == {"featured", "top_chinese", "top_global", "categories"}
    cats = data["categories"]
    assert len(cats) == len(server_mod.GENRE_SHELVES)
    for cat in cats:
        assert len(cat["items"]) == 50
        top = cat["items"][0]
        assert top["latest_episode"]["title"] == "Latest Ep"
        assert top["latest_episode"]["duration"] == 1234
        assert top["latest_episode"]["pub_date"] == "Thu, 12 Nov 2026 10:00:00 GMT"
        assert top["latest_episode"]["audio_url"] == "https://e/latest.mp3"
        assert top["latest_episode"]["id"] == f"{top['id']}_ep1"
        # Only the #1 show carries the spotlight field.
        assert "latest_episode" not in cat["items"][1]


def test_discover_latest_episode_failure_omits_field_per_category(monkeypatch):
    calls = {"n": 0}

    async def failing_latest(feed_url, feed_id):
        calls["n"] += 1
        raise RuntimeError("feed dead")

    _patch_discover(monkeypatch, _fake_shelf_items(50), failing_latest)
    headers = {"Authorization": f"Bearer {AUTH_TOKEN}"}
    resp = client.get("/api/v1/discover", headers=headers)
    assert resp.status_code == 200, resp.text
    cats = resp.json()["categories"]
    assert len(cats) == len(server_mod.GENRE_SHELVES)
    for cat in cats:
        assert len(cat["items"]) == 50  # shelf itself unaffected
        assert "latest_episode" not in cat["items"][0]
    assert calls["n"] == len(cats)  # every shelf attempted independently


def test_fetch_latest_episode_picks_newest_by_pub_date_and_caches():
    from amber_podcast.aggregator.itunes import ApplePodcastAggregator

    agg = ApplePodcastAggregator()
    calls = {"n": 0}

    async def fake_fetch(url, feed_id):
        calls["n"] += 1
        return {"feed": {"id": feed_id}, "episodes": [
            {"id": f"{feed_id}_old", "title": "Old", "audio_url": "https://e/old.mp3",
             "duration": 60, "pub_date": "Wed, 11 Nov 2026 10:00:00 GMT", "guid": "g1"},
            {"id": f"{feed_id}_new", "title": "New", "audio_url": "https://e/new.mp3",
             "duration": 120, "pub_date": "Thu, 12 Nov 2026 10:00:00 GMT", "guid": "g2"},
        ]}

    agg.fetch_and_parse_feed = fake_fetch
    first = asyncio.run(agg.fetch_latest_episode("https://example.com/rss", "feed_le"))
    second = asyncio.run(agg.fetch_latest_episode("https://example.com/rss", "feed_le"))
    assert calls["n"] == 1  # second call served from the independent cache
    assert first == second
    assert first["title"] == "New"  # by pubDate, not document order
    assert first["duration"] == 120
    assert set(first) == {"id", "title", "duration", "pub_date", "audio_url"}


def test_fetch_latest_episode_never_fatal():
    from amber_podcast.aggregator.itunes import ApplePodcastAggregator

    agg = ApplePodcastAggregator()

    async def boom(url, feed_id):
        raise RuntimeError("network down")

    agg.fetch_and_parse_feed = boom
    assert asyncio.run(agg.fetch_latest_episode("https://example.com/dead", "feed_dead")) is None


# --- C1: per-word subtitle timings must survive into full_mapping ---


def test_native_mapping_segment_keeps_word_timestamps():
    """Chinese-native episodes: ASR words are the Chinese timeline — they must
    land in zh_words so the player can highlight word by word. Dropping them
    (previous behaviour) leaves the client with segment-level timing only."""
    from amber_podcast.pipeline.asr import ASRSegment

    seg = ASRSegment(
        index=3, speaker="SPEAKER_00", text="今天我们聊聊产品设计",
        start=10.0, end=14.5,
        words=[
            {"word": "今天", "start": 10.0, "end": 10.4},
            {"word": "我们", "start": 10.4, "end": 10.9},
        ],
    )
    m = server_mod._native_mapping_segment(3, seg)
    assert m["index"] == 3
    assert m["zh_display"] == "今天我们聊聊产品设计"
    assert [w["word"] for w in m["zh_words"]] == ["今天", "我们"]
    assert m["zh_words"][0]["start"] == 10.0
    assert m["en_words"] is None  # no English track in a native episode
    assert m["zh_range"] == {"start": 10.0, "end": 14.5}

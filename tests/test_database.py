import pytest
import tempfile
import os
from amber_podcast.database import Database

@pytest.fixture
def db():
    with tempfile.NamedTemporaryFile(suffix=".db", delete=False) as f:
        tmp_path = f.name
    database = Database(db_path=tmp_path)
    yield database
    if os.path.exists(tmp_path):
        os.remove(tmp_path)

def test_feed_crud(db):
    feed = db.upsert_feed(
        feed_id="feed_test_1",
        source_type="apple_rss",
        title="Huberman Lab",
        author="Andrew Huberman",
        feed_url="https://feeds.hubermanlab.com/rss",
        cover_url="https://example.com/cover.jpg",
        description="Neuroscience podcast",
        auto_translate=1
    )
    assert feed is not None
    assert feed["title"] == "Huberman Lab"
    assert feed["auto_translate"] == 1

    fetched = db.get_feed("feed_test_1")
    assert fetched is not None
    assert fetched["author"] == "Andrew Huberman"

    feeds = db.list_feeds()
    assert len(feeds) == 1
    assert feeds[0]["id"] == "feed_test_1"

    # Update auto_translate
    db.upsert_feed(
        feed_id="feed_test_1",
        source_type="apple_rss",
        title="Huberman Lab (Updated)",
        author="Andrew Huberman",
        feed_url="https://feeds.hubermanlab.com/rss",
        cover_url="https://example.com/cover.jpg",
        description="Neuroscience podcast",
        auto_translate=0
    )
    updated = db.get_feed("feed_test_1")
    assert updated["title"] == "Huberman Lab (Updated)"
    assert updated["auto_translate"] == 0

def test_episode_crud_and_status(db):
    db.upsert_feed(
        feed_id="feed_test_1",
        source_type="apple_rss",
        title="Test Feed",
        author="Host",
        feed_url="https://example.com/rss",
        cover_url="",
        description=""
    )

    ep = db.upsert_episode(
        episode_id="ep_101",
        feed_id="feed_test_1",
        title="Dopamine & Focus",
        audio_url="https://example.com/ep101.mp3",
        duration=3600,
        pub_date="2026-10-10",
        shownotes="Shownotes with timestamps: 05:20 Intro, 12:45 Dopamine baselines",
        guid="guid-101"
    )
    assert ep is not None
    assert ep["status"] == "idle"
    assert ep["progress"] == 0

    # Status update: translating
    db.update_episode_status("ep_101", status="translating", progress=45)
    ep_updating = db.get_episode("ep_101")
    assert ep_updating["status"] == "translating"
    assert ep_updating["progress"] == 45

    # Status update: ready with gdrive
    db.update_episode_status("ep_101", status="ready", progress=100, gdrive_folder_id="1ABCxyz")
    ep_ready = db.get_episode("ep_101")
    assert ep_ready["status"] == "ready"
    assert ep_ready["progress"] == 100
    assert ep_ready["gdrive_folder_id"] == "1ABCxyz"

    episodes = db.list_episodes(feed_id="feed_test_1")
    assert len(episodes) == 1

def test_playback_progress(db):
    db.upsert_feed(
        feed_id="feed_test_1",
        source_type="apple_rss",
        title="Test Feed",
        author="Host",
        feed_url="https://example.com/rss",
        cover_url="",
        description=""
    )
    db.upsert_episode(
        episode_id="ep_101",
        feed_id="feed_test_1",
        title="Episode 1",
        audio_url="https://example.com/ep1.mp3"
    )

    db.update_playback_progress(
        episode_id="ep_101",
        position_ms=124000,
        duration_ms=3600000,
        track_mode="alternating",
        is_finished=0
    )

    prog = db.get_playback_progress("ep_101")
    assert prog is not None
    assert prog["position_ms"] == 124000
    assert prog["track_mode"] == "alternating"
    assert prog["is_finished"] == 0

    # Update position to finished
    db.update_playback_progress(
        episode_id="ep_101",
        position_ms=3600000,
        duration_ms=3600000,
        track_mode="chinese",
        is_finished=1
    )
    prog_finished = db.get_playback_progress("ep_101")
    assert prog_finished["is_finished"] == 1

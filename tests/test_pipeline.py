import pytest
import os
import tempfile
import json
from pathlib import Path
from amber_podcast.pipeline.translator import TranslatedSegment
from amber_podcast.pipeline.tts.base import BaseTTSProvider, TTSResult
from amber_podcast.pipeline.aligner import AlignmentEngine
from amber_podcast.pipeline.archiver import EpisodeArchiver

class MockTTSProvider(BaseTTSProvider):
    def get_voice_for_speaker(self, speaker_id: str) -> str:
        return "mock_voice"

    async def synthesize(self, text: str, voice: str, output_path: str, emotion_style=None) -> TTSResult:
        # Create a valid minimal MP3 file using ffmpeg silent audio
        cmd = [
            "/root/.hermes/tools/ffmpeg-9.0.1-linux-x64/bin/ffmpeg", "-y",
            "-f", "lavfi", "-i", "anullsrc=r=24000:cl=mono",
            "-t", "1.5", "-c:a", "libmp3lame", output_path
        ]
        import subprocess
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        words = [
            {"word": "测试", "start": 0.0, "end": 0.6},
            {"word": "播客", "start": 0.7, "end": 1.4}
        ]
        return TTSResult(audio_path=output_path, duration_sec=1.5, word_timestamps=words)

def test_aligner_and_archiver():
    import asyncio
    asyncio.run(_async_test_aligner_and_archiver())

async def _async_test_aligner_and_archiver():
    with tempfile.TemporaryDirectory() as tmpdir:
        work_path = Path(tmpdir) / "work"
        archive_path = Path(tmpdir) / "archive"

        segments = [
            TranslatedSegment(
                index=0,
                speaker="SPEAKER_00",
                en_text="Welcome to the show.",
                display_zh="欢迎收听节目。",
                tts_spoken_zh="哎欢迎大家收听咱们的节目。",
                emotion_style="热情开朗",
                en_start=0.0,
                en_end=2.0,
                en_words=[{"word": "Welcome", "start": 0.0, "end": 0.8}]
            ),
            TranslatedSegment(
                index=1,
                speaker="SPEAKER_01",
                en_text="Thanks for having me.",
                display_zh="很高兴来到这里。",
                tts_spoken_zh="很开心能跟您聊聊。",
                emotion_style="轻松回应",
                en_start=2.5,
                en_end=4.0,
                en_words=[{"word": "Thanks", "start": 2.5, "end": 3.2}]
            )
        ]

        # 1. Run aligner
        mock_tts = MockTTSProvider()
        aligner = AlignmentEngine(tts_provider=mock_tts)
        bundle = await aligner.build_dual_track_bundle(
            episode_id="ep_test_align",
            segments=segments,
            work_dir=work_path
        )

        assert os.path.exists(bundle["chinese_audio_path"])
        assert os.path.exists(bundle["timing_sync_path"])
        assert os.path.exists(bundle["full_mapping_path"])

        # Check timing_sync.json content
        with open(bundle["timing_sync_path"], "r", encoding="utf-8") as f:
            timing_data = json.load(f)
        assert len(timing_data) == 2
        assert timing_data[0]["speaker"] == "SPEAKER_00"
        assert timing_data[1]["speaker"] == "SPEAKER_01"
        assert "en" in timing_data[0]
        assert "zh" in timing_data[0]

        # Check full_mapping.json content
        with open(bundle["full_mapping_path"], "r", encoding="utf-8") as f:
            mapping_data = json.load(f)
        assert len(mapping_data) == 2
        assert mapping_data[0]["zh_display"] == "欢迎收听节目。"
        assert len(mapping_data[0]["zh_words"]) == 2

        # 2. Run archiver
        archiver = EpisodeArchiver(gdrive_dir=archive_path)
        archived = archiver.archive_episode_bundle(
            episode_id="ep_test_align",
            chinese_audio_path=bundle["chinese_audio_path"],
            timing_sync_path=bundle["timing_sync_path"],
            full_mapping_path=bundle["full_mapping_path"],
            chapters=[{"title": "开场介绍", "start_sec": 0.0}],
            article_markdown="# 精读笔记"
        )

        assert os.path.exists(archived["chinese_audio"])
        assert os.path.exists(archived["timing_sync"])
        assert os.path.exists(archived["full_mapping"])
        assert os.path.exists(archived["chapters"])
        assert os.path.exists(archived["article"])

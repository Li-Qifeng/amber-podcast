import asyncio
import edge_tts
import mutagen
import re
from typing import List, Dict, Any, Optional
from amber_podcast.pipeline.tts.base import BaseTTSProvider, TTSResult

class EdgeTTSProvider(BaseTTSProvider):
    # Distinct expressive voices for different speakers
    VOICE_MAP = {
        "SPEAKER_00": "zh-CN-YunxiNeural",     # 阳光青年男声（适合主讲人/主播）
        "SPEAKER_01": "zh-CN-XiaoxiaoNeural",   # 温暖知性女声（适合嘉宾A）
        "SPEAKER_02": "zh-CN-YunjianNeural",   # 沉稳成熟男声（适合嘉宾B）
        "SPEAKER_03": "zh-CN-XiaoyiNeural",     # 亲切活力女声（适合嘉宾C）
    }

    def get_voice_for_speaker(self, speaker_id: str) -> str:
        return self.VOICE_MAP.get(speaker_id, "zh-CN-YunxiNeural")

    async def synthesize(self, text: str, voice: str, output_path: str, emotion_style: Optional[str] = None) -> TTSResult:
        """Synthesize text using edge-tts with WordBoundary timestamp capture."""
        # Strip internal tags like <short pause> for edge-tts
        clean_text = re.sub(r"<[^>]+>", "", text).strip()
        if not clean_text:
            clean_text = "..."

        communicate = edge_tts.Communicate(clean_text, voice)
        word_timestamps: List[Dict[str, Any]] = []

        with open(output_path, "wb") as f:
            async for chunk in communicate.stream():
                if chunk["type"] == "audio":
                    f.write(chunk["data"])
                elif chunk["type"] == "WordBoundary":
                    # Offset is in 100-nanosecond units (ticks)
                    offset_sec = chunk["offset"] / 10_000_000.0
                    duration_sec = chunk["duration"] / 10_000_000.0
                    word_timestamps.append({
                        "word": chunk["text"],
                        "start": round(offset_sec, 3),
                        "end": round(offset_sec + duration_sec, 3)
                    })

        # Calculate exact audio duration using mutagen or ffprobe
        duration_sec = 0.0
        try:
            mf = mutagen.File(output_path)
            if mf is not None and getattr(mf, "info", None) is not None:
                duration_sec = float(mf.info.length)
        except Exception:
            pass

        if duration_sec <= 0.0 and word_timestamps:
            duration_sec = word_timestamps[-1]["end"]

        return TTSResult(
            audio_path=output_path,
            duration_sec=duration_sec,
            word_timestamps=word_timestamps
        )

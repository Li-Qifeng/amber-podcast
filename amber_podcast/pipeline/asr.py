import httpx
import os
import json
from typing import List, Dict, Any, Optional
from amber_podcast.config import GROQ_API_KEY

class ASRSegment:
    def __init__(self, index: int, speaker: str, text: str, start: float, end: float, words: List[Dict[str, Any]]):
        self.index = index
        self.speaker = speaker
        self.text = text
        self.start = round(start, 3)
        self.end = round(end, 3)
        self.words = words

    def to_dict(self) -> Dict[str, Any]:
        return {
            "index": self.index,
            "speaker": self.speaker,
            "text": self.text,
            "start": self.start,
            "end": self.end,
            "words": self.words
        }

class ASREngine:
    def __init__(self, api_key: Optional[str] = None, timeout: float = 120.0):
        self.api_key = api_key or GROQ_API_KEY
        self.timeout = timeout
        self.endpoint = "https://api.groq.com/openai/v1/audio/transcriptions"

    async def transcribe_audio_file(self, audio_file_path: str, language: str = "en") -> List[ASRSegment]:
        """Transcribe an audio file using Groq Whisper Turbo with word and segment timestamps."""
        if not os.path.exists(audio_file_path):
            raise FileNotFoundError(f"Audio file not found: {audio_file_path}")

        headers = {
            "Authorization": f"Bearer {self.api_key}"
        }

        with open(audio_file_path, "rb") as f:
            files = {
                "file": (os.path.basename(audio_file_path), f, "audio/mpeg"),
            }
            data = {
                "model": "whisper-large-v3-turbo",
                "response_format": "verbose_json",
                "timestamp_granularities[]": ["segment", "word"],
                "temperature": "0.0",
                "language": language
            }

            async with httpx.AsyncClient(timeout=self.timeout) as client:
                resp = await client.post(self.endpoint, headers=headers, files=files, data=data)
                resp.raise_for_status()
                result = resp.json()

        return self.parse_verbose_json(result)

    def parse_verbose_json(self, data: Dict[str, Any]) -> List[ASRSegment]:
        """Convert Whisper verbose_json segments and words into structured ASRSegments."""
        raw_segments = data.get("segments", [])
        raw_words = data.get("words", [])

        # Index words by start time for quick segment association
        segments: List[ASRSegment] = []
        current_speaker = "SPEAKER_00"

        for idx, seg in enumerate(raw_segments):
            start = float(seg.get("start", 0.0))
            end = float(seg.get("end", 0.0))
            text = seg.get("text", "").strip()

            # Filter words within this segment's time window
            seg_words = [
                {
                    "word": w.get("word", "").strip(),
                    "start": round(float(w.get("start", start)), 3),
                    "end": round(float(w.get("end", end)), 3)
                }
                for w in raw_words
                if start - 0.1 <= float(w.get("start", 0.0)) <= end + 0.1
            ]

            # Heuristic turn-taking detection if gap between segments is large (> 0.8s)
            if idx > 0 and (start - float(raw_segments[idx - 1].get("end", 0.0))) > 0.8:
                # Toggle speaker for multi-speaker interview feel
                current_speaker = "SPEAKER_01" if current_speaker == "SPEAKER_00" else "SPEAKER_00"

            segments.append(ASRSegment(
                index=idx,
                speaker=current_speaker,
                text=text,
                start=start,
                end=end,
                words=seg_words
            ))

        return segments

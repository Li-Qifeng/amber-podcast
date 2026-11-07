import httpx
import os
import json
import subprocess
from pathlib import Path
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
    def __init__(self, api_key: Optional[str] = None, timeout: float = 180.0):
        self.api_key = api_key or GROQ_API_KEY
        self.timeout = timeout
        self.endpoint = "https://api.groq.com/openai/v1/audio/transcriptions"

    def _get_duration(self, audio_path: str) -> float:
        """Get duration of audio file via ffprobe."""
        cmd = ["ffprobe", "-i", audio_path, "-show_entries", "format=duration", "-v", "quiet", "-of", "csv=p=0"]
        try:
            out = subprocess.check_output(cmd).decode().strip()
            return float(out)
        except Exception:
            return 0.0

    async def transcribe_audio_file(self, audio_file_path: str, language: str = "en") -> List[ASRSegment]:
        """Transcribe audio using Groq Whisper Turbo, automatically chunking if > 20MB."""
        if not os.path.exists(audio_file_path):
            raise FileNotFoundError(f"Audio file not found: {audio_file_path}")

        file_size_mb = os.path.getsize(audio_file_path) / (1024 * 1024)
        if file_size_mb > 20.0:
            return await self._transcribe_chunked(audio_file_path, language=language)
        else:
            return await self._transcribe_single(audio_file_path, time_offset=0.0, start_index=0, language=language)

    async def _transcribe_single(
        self,
        audio_file_path: str,
        time_offset: float = 0.0,
        start_index: int = 0,
        language: str = "en"
    ) -> List[ASRSegment]:
        """Transcribe a single audio file and apply time offset."""
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

        return self.parse_verbose_json(result, time_offset=time_offset, start_index=start_index)

    async def _transcribe_chunked(
        self,
        audio_file_path: str,
        chunk_duration_sec: int = 600,
        language: str = "en"
    ) -> List[ASRSegment]:
        """Split large audio into 10-minute segments using ffmpeg and transcribe sequentially."""
        work_dir = Path(audio_file_path).parent / "asr_chunks"
        work_dir.mkdir(parents=True, exist_ok=True)

        for old in work_dir.glob("chunk_*.mp3"):
            try:
                old.unlink()
            except Exception:
                pass

        chunk_pattern = str(work_dir / "chunk_%03d.mp3")
        cmd = [
            "ffmpeg", "-y", "-i", audio_file_path,
            "-f", "segment", "-segment_time", str(chunk_duration_sec),
            "-ac", "1", "-ar", "16000", "-c:a", "libmp3lame", "-b:a", "48k",
            chunk_pattern
        ]
        subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        chunk_files = sorted(list(work_dir.glob("chunk_*.mp3")))
        all_segments: List[ASRSegment] = []
        current_time_offset = 0.0
        current_index = 0

        for chunk in chunk_files:
            chunk_dur = self._get_duration(str(chunk))
            segs = await self._transcribe_single(
                str(chunk),
                time_offset=current_time_offset,
                start_index=current_index,
                language=language
            )
            all_segments.extend(segs)
            current_index += len(segs)
            current_time_offset += chunk_dur

        return all_segments

    def parse_verbose_json(
        self,
        data: Dict[str, Any],
        time_offset: float = 0.0,
        start_index: int = 0
    ) -> List[ASRSegment]:
        """Convert Whisper verbose_json segments and words into structured ASRSegments with offset."""
        raw_segments = data.get("segments", [])
        raw_words = data.get("words", [])

        segments: List[ASRSegment] = []
        current_speaker = "SPEAKER_00"

        for idx, seg in enumerate(raw_segments):
            start = round(float(seg.get("start", 0.0)) + time_offset, 3)
            end = round(float(seg.get("end", 0.0)) + time_offset, 3)
            text = seg.get("text", "").strip()

            seg_words = [
                {
                    "word": w.get("word", "").strip(),
                    "start": round(float(w.get("start", 0.0)) + time_offset, 3),
                    "end": round(float(w.get("end", 0.0)) + time_offset, 3)
                }
                for w in raw_words
                if (float(seg.get("start", 0.0)) - 0.1) <= float(w.get("start", 0.0)) <= (float(seg.get("end", 0.0)) + 0.1)
            ]

            if idx > 0 and (float(seg.get("start", 0.0)) - float(raw_segments[idx - 1].get("end", 0.0))) > 0.8:
                current_speaker = "SPEAKER_01" if current_speaker == "SPEAKER_00" else "SPEAKER_00"

            segments.append(ASRSegment(
                index=start_index + idx,
                speaker=current_speaker,
                text=text,
                start=start,
                end=end,
                words=seg_words
            ))

        return segments

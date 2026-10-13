from abc import ABC, abstractmethod
from typing import List, Dict, Any, Optional

class TTSResult:
    def __init__(self, audio_path: str, duration_sec: float, word_timestamps: Optional[List[Dict[str, Any]]] = None):
        self.audio_path = audio_path
        self.duration_sec = round(duration_sec, 3)
        self.word_timestamps = word_timestamps or []

class BaseTTSProvider(ABC):
    @abstractmethod
    async def synthesize(self, text: str, voice: str, output_path: str, emotion_style: Optional[str] = None) -> TTSResult:
        """Synthesize text to audio and return duration and word timestamps."""
        pass

    @abstractmethod
    def get_voice_for_speaker(self, speaker_id: str) -> str:
        """Map a speaker ID (e.g. SPEAKER_00, SPEAKER_01) to a distinct voice."""
        pass

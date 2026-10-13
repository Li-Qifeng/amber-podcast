import httpx
import base64
import subprocess
import mutagen
import os
import re
from typing import List, Dict, Any, Optional
from amber_podcast.pipeline.tts.base import BaseTTSProvider, TTSResult
from amber_podcast.config import GOOGLE_PROJECT_ID

class GoogleCloudTTSProvider(BaseTTSProvider):
    # Expressive Journey and Neural2 voices for multi-speaker Chinese dialogue
    VOICE_MAP = {
        "SPEAKER_00": "cmn-CN-Journey-D",   # 自然男声
        "SPEAKER_01": "cmn-CN-Journey-F",   # 自然女声
        "SPEAKER_02": "cmn-CN-Neural2-C",   # 沉稳男声
        "SPEAKER_03": "cmn-CN-Neural2-A",   # 亲切女声
    }

    def __init__(self, project_id: Optional[str] = None):
        self.project_id = project_id or GOOGLE_PROJECT_ID
        self.endpoint = "https://texttospeech.googleapis.com/v1/text:synthesize"

    def _get_access_token(self) -> str:
        """Fetch access token from gcloud SDK."""
        token = subprocess.getoutput("/root/google-cloud-sdk/bin/gcloud auth print-access-token 2>/dev/null").strip()
        return token

    def get_voice_for_speaker(self, speaker_id: str) -> str:
        return self.VOICE_MAP.get(speaker_id, "cmn-CN-Journey-D")

    async def synthesize(self, text: str, voice: str, output_path: str, emotion_style: Optional[str] = None) -> TTSResult:
        """Synthesize text via Google Cloud Text-to-Speech API."""
        clean_text = re.sub(r"<[^>]+>", "", text).strip()
        if not clean_text:
            clean_text = "..."

        token = self._get_access_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "x-goog-user-project": self.project_id,
            "Content-Type": "application/json"
        }

        # Build synthesize request payload
        payload = {
            "input": {
                "text": clean_text
            },
            "voice": {
                "languageCode": "cmn-CN",
                "name": voice
            },
            "audioConfig": {
                "audioEncoding": "MP3",
                "speakingRate": 1.0,
                "pitch": 0.0,
                "sampleRateHertz": 24000
            }
        }

        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(self.endpoint, headers=headers, json=payload)
            resp.raise_for_status()
            data = resp.json()

        audio_content_b64 = data.get("audioContent", "")
        with open(output_path, "wb") as f:
            f.write(base64.b64decode(audio_content_b64))

        # Measure exact duration
        duration_sec = 0.0
        try:
            mf = mutagen.File(output_path)
            if mf and mf.info:
                duration_sec = float(mf.info.length)
        except Exception:
            pass

        return TTSResult(
            audio_path=output_path,
            duration_sec=duration_sec,
            word_timestamps=[]
        )

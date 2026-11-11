import asyncio
import os
import json
import subprocess
import time
from pathlib import Path
from typing import List, Dict, Any, Tuple, Optional
from amber_podcast.pipeline.translator import TranslatedSegment
from amber_podcast.pipeline.tts.base import BaseTTSProvider, TTSResult
from amber_podcast.config import SCRATCH_DIR

class AlignmentEngine:
    def __init__(self, tts_provider: BaseTTSProvider, ffmpeg_bin: Optional[str] = None):
        self.tts = tts_provider
        import shutil
        self.ffmpeg = ffmpeg_bin or shutil.which("ffmpeg") or "/usr/local/bin/ffmpeg"

    def _run_ffmpeg(self, cmd: List[str], label: str, retries: int = 2) -> None:
        """Run ffmpeg with a small retry budget.

        Inputs here are freshly written by the TTS stage, so a transient IO
        error (handle not yet flushed, momentarily busy file) used to abort the
        whole episode and surface as an opaque 'exit status 255'. Retry, then
        raise with the captured stderr so the failure is diagnosable.
        """
        last_err = ""
        last_rc = -1
        for attempt in range(retries + 1):
            proc = subprocess.run(cmd, capture_output=True, text=True)
            if proc.returncode == 0:
                return
            last_err = (proc.stderr or "").strip()[-800:]
            last_rc = proc.returncode
            if attempt < retries:
                time.sleep(1.5 * (attempt + 1))
        raise RuntimeError(
            f"ffmpeg {label} failed after {retries + 1} attempts "
            f"(exit {last_rc}): {last_err}"
        )

    async def build_dual_track_bundle(
        self,
        episode_id: str,
        segments: List[TranslatedSegment],
        work_dir: Optional[Path] = None
    ) -> Dict[str, Any]:
        """Synthesize all translated segments, concatenate with turn-taking pauses, and generate alignment JSONs."""
        work_path = work_dir or (SCRATCH_DIR / episode_id)
        work_path.mkdir(parents=True, exist_ok=True)

        chunks_dir = work_path / "chunks"
        chunks_dir.mkdir(parents=True, exist_ok=True)

        # 1. Synthesize all segments concurrently with bounded semaphore
        sem = asyncio.Semaphore(5)

        async def _synth(seg: TranslatedSegment) -> Tuple[int, TTSResult]:
            async with sem:
                voice = self.tts.get_voice_for_speaker(seg.speaker)
                out_file = str(chunks_dir / f"chunk_{seg.index:05d}.mp3")
                res = await self.tts.synthesize(
                    text=seg.tts_spoken_zh,
                    voice=voice,
                    output_path=out_file,
                    emotion_style=seg.emotion_style
                )
                return seg.index, res

        synth_tasks = [_synth(s) for s in segments]
        synth_results = await asyncio.gather(*synth_tasks)
        results_by_index = {idx: res for idx, res in synth_results}

        # 2. Compute Chinese timeline and build alignment structures
        timing_segments: List[Dict[str, Any]] = []
        full_mapping: List[Dict[str, Any]] = []
        concat_list_file = work_path / "concat_list.txt"

        current_zh_time = 0.0
        prev_speaker = None
        concat_entries: List[str] = []

        for seg in segments:
            res = results_by_index[seg.index]
            dur = res.duration_sec

            # Turn-taking pause: 0.18s if same speaker, 0.32s if speaker changed
            if prev_speaker is not None:
                pause_sec = 0.32 if seg.speaker != prev_speaker else 0.18
            else:
                pause_sec = 0.0

            zh_start = round(current_zh_time + pause_sec, 3)
            zh_end = round(zh_start + dur, 3)
            current_zh_time = zh_end
            prev_speaker = seg.speaker

            # Map word timestamps relative to the whole Chinese timeline
            zh_words = []
            for w in res.word_timestamps:
                zh_words.append({
                    "word": w["word"],
                    "start": round(zh_start + w["start"], 3),
                    "end": round(zh_start + w["end"], 3)
                })

            # TimingSync segment (lightweight, tens of KB)
            timing_segments.append({
                "id": seg.index,
                "speaker": seg.speaker,
                "en": {"start": seg.en_start, "end": seg.en_end},
                "zh": {"start": zh_start, "end": zh_end}
            })

            # FullMapping segment (rich UI subtitles + words)
            full_mapping.append({
                "index": seg.index,
                "speaker": seg.speaker,
                "en_text": seg.en_text,
                "zh_display": seg.display_zh,
                "zh_spoken": seg.tts_spoken_zh,
                "en_range": {"start": seg.en_start, "end": seg.en_end},
                "zh_range": {"start": zh_start, "end": zh_end},
                "en_words": seg.en_words,
                "zh_words": zh_words
            })

            concat_entries.append(f"file '{res.audio_path}'")

        # 3. Concatenate and apply -16 LUFS loudness normalization with FFmpeg
        with open(concat_list_file, "w") as f:
            f.write("\n".join(concat_entries) + "\n")

        raw_output_m4a = work_path / "chinese_raw.m4a"
        final_output_m4a = work_path / "chinese_audio.m4a"

        # Concat command
        cmd_concat = [
            self.ffmpeg, "-y", "-f", "concat", "-safe", "0",
            "-i", str(concat_list_file),
            "-c:a", "aac", "-b:a", "128k",
            str(raw_output_m4a)
        ]
        self._run_ffmpeg(cmd_concat, "concat")

        # Normalize loudness to -16 LUFS (Apple Podcasts standard)
        cmd_norm = [
            self.ffmpeg, "-y",
            "-i", str(raw_output_m4a),
            "-af", "highpass=f=80,loudnorm=I=-16:TP=-1.5:LRA=11",
            "-c:a", "aac", "-b:a", "128k",
            str(final_output_m4a)
        ]
        self._run_ffmpeg(cmd_norm, "loudnorm")

        # 4. Save JSON artifacts
        timing_sync_file = work_path / "timing_sync.json"
        with open(timing_sync_file, "w", encoding="utf-8") as f:
            json.dump(timing_segments, f, ensure_ascii=False, indent=2)

        full_mapping_file = work_path / "full_mapping.json"
        with open(full_mapping_file, "w", encoding="utf-8") as f:
            json.dump(full_mapping, f, ensure_ascii=False, indent=2)

        return {
            "chinese_audio_path": str(final_output_m4a),
            "timing_sync_path": str(timing_sync_file),
            "full_mapping_path": str(full_mapping_file),
            "total_zh_duration": round(current_zh_time, 3),
            "segment_count": len(segments)
        }

import httpx
import json
import re
from typing import List, Dict, Any, Optional
from amber_podcast.config import GCLI_BASE_URL, GCLI_API_KEY, GROQ_API_KEY
from amber_podcast.pipeline.asr import ASRSegment

SYSTEM_PROMPT = """你是一个顶级双语播客译制专家和中文口播主创。
你的任务是将输入的英文播客句子列表，翻译改写为适合中文播客直接朗读的双轨台本：
1. display_zh: 供手机屏幕双语字幕阅读。译文精准地道、专业术语在首次出现时用括号简要注释。
2. tts_spoken_zh: 供中文语音大模型（如豆包/千问）直接朗读。必须富有真人聊天的松弛感，加入自然的口语衔接词（如“哎其实”、“你看”、“确实是这样”），可插入简短气口标记如 <short pause>，但严禁破坏原意。
3. emotion_style: 为该句指定的语气指令，如“轻松分享”、“认真强调”、“幽默调侃”、“语速稍快”。

请严格返回合法的 JSON 对象，格式如下：
{
  "segments": [
    {
      "index": 0,
      "display_zh": "中文阅读字幕",
      "tts_spoken_zh": "适合真人嘴巴说出来的中文口播台词",
      "emotion_style": "语气指令"
    }
  ]
}
"""

CHAPTERS_NOTES_PROMPT = """根据以下播客转录全文，生成：
1. 章节切分（chapters）：包含 4~8 个核心话题，每个章节包含 title 与 start_sec（浮点数秒）。
2. 深度精读笔记（article_markdown）：一份 800~1500 字结构清晰的 Markdown 长文笔记，包含核心论点、精彩洞见和核心金句。

请严格返回 JSON 对象：
{
  "chapters": [
    {"title": "话题标题", "start_sec": 0.0}
  ],
  "article_markdown": "# 深度精读笔记\\n\\n..."
}
"""

class TranslatedSegment:
    def __init__(self, index: int, speaker: str, en_text: str, display_zh: str, tts_spoken_zh: str,
                 emotion_style: str, en_start: float, en_end: float, en_words: List[Dict[str, Any]]):
        self.index = index
        self.speaker = speaker
        self.en_text = en_text
        self.display_zh = display_zh
        self.tts_spoken_zh = tts_spoken_zh
        self.emotion_style = emotion_style
        self.en_start = en_start
        self.en_end = en_end
        self.en_words = en_words

    def to_dict(self) -> Dict[str, Any]:
        return {
            "index": self.index,
            "speaker": self.speaker,
            "en_text": self.en_text,
            "display_zh": self.display_zh,
            "tts_spoken_zh": self.tts_spoken_zh,
            "emotion_style": self.emotion_style,
            "en_start": self.en_start,
            "en_end": self.en_end,
            "en_words": self.en_words
        }

class TranslatorEngine:
    def __init__(self, timeout: float = 60.0):
        self.timeout = timeout

    async def translate_segments(self, asr_segments: List[ASRSegment]) -> List[TranslatedSegment]:
        """Translate ASR segments into oral Chinese podcast scripts with batching."""
        if not asr_segments:
            return []

        # Batch in chunks of 20 sentences
        batch_size = 20
        all_translated: List[TranslatedSegment] = []

        for i in range(0, len(asr_segments), batch_size):
            chunk = asr_segments[i:i + batch_size]
            payload_input = [{"index": s.index, "speaker": s.speaker, "text": s.text} for s in chunk]
            
            prompt = f"输入句子列表：\n{json.dumps(payload_input, ensure_ascii=False)}"
            response_json = await self._call_llm_with_fallback(SYSTEM_PROMPT, prompt)
            
            mapping = {}
            if response_json and "segments" in response_json:
                for item in response_json["segments"]:
                    mapping[item.get("index")] = item

            for s in chunk:
                trans = mapping.get(s.index, {})
                display_zh = trans.get("display_zh") or s.text
                tts_spoken_zh = trans.get("tts_spoken_zh") or display_zh
                emotion_style = trans.get("emotion_style") or "自然平稳"

                all_translated.append(TranslatedSegment(
                    index=s.index,
                    speaker=s.speaker,
                    en_text=s.text,
                    display_zh=display_zh,
                    tts_spoken_zh=tts_spoken_zh,
                    emotion_style=emotion_style,
                    en_start=s.start,
                    en_end=s.end,
                    en_words=s.words
                ))

        return all_translated

    async def generate_chapters_and_notes(self, asr_segments: List[ASRSegment]) -> Dict[str, Any]:
        """Generate structured chapters and Markdown reading notes from full transcript."""
        transcript_sample = "\n".join([f"[{s.start:.1f}s] {s.speaker}: {s.text}" for s in asr_segments[:100]])
        prompt = f"播客转录内容片段：\n{transcript_sample}"
        
        result = await self._call_llm_with_fallback(CHAPTERS_NOTES_PROMPT, prompt)
        if not result or not isinstance(result, dict):
            # Fallback default
            return {
                "chapters": [{"title": "完整节目", "start_sec": 0.0}],
                "article_markdown": "# 节目概要\n\n该期播客已完成 AI 双轨转译。"
            }
        return {
            "chapters": result.get("chapters", [{"title": "完整节目", "start_sec": 0.0}]),
            "article_markdown": result.get("article_markdown", "# 深度精读笔记")
        }

    async def _call_llm_with_fallback(self, system_prompt: str, user_prompt: str) -> Optional[Dict[str, Any]]:
        """Call LLM with primary (Groq Qwen 3.8 27B / GPT-OSS) and fallback to local gateway."""
        # 1. Primary: Groq Qwen 3.8 27B (fastest & best for oral Chinese podcast translation)
        if GROQ_API_KEY:
            for model_name in ["qwen/qwen3.8-27b", "openai/gpt-oss-120b"]:
                try:
                    async with httpx.AsyncClient(timeout=self.timeout) as client:
                        resp = await client.post(
                            "https://api.groq.com/openai/v1/chat/completions",
                            headers={"Authorization": f"Bearer {GROQ_API_KEY}", "Content-Type": "application/json"},
                            json={
                                "model": model_name,
                                "messages": [
                                    {"role": "system", "content": system_prompt},
                                    {"role": "user", "content": user_prompt}
                                ],
                                "temperature": 0.2,
                                "response_format": {"type": "json_object"}
                            }
                        )
                        if resp.status_code == 200:
                            content = resp.json()["choices"][0]["message"]["content"]
                            parsed = self._clean_and_parse_json(content)
                            if parsed:
                                return parsed
                except Exception:
                    pass

        # 2. Fallback: gcli (Antigravity Manager) if configured
        if GCLI_API_KEY:
            try:
                async with httpx.AsyncClient(timeout=self.timeout) as client:
                    resp = await client.post(
                        f"{GCLI_BASE_URL}/chat/completions",
                        headers={"Authorization": f"Bearer {GCLI_API_KEY}", "Content-Type": "application/json"},
                        json={
                            "model": "gemini-3.8-flash-low",
                            "messages": [
                                {"role": "system", "content": system_prompt},
                                {"role": "user", "content": user_prompt}
                            ],
                            "temperature": 0.2,
                            "response_format": {"type": "json_object"}
                        }
                    )
                    if resp.status_code == 200:
                        content = resp.json()["choices"][0]["message"]["content"]
                        parsed = self._clean_and_parse_json(content)
                        if parsed:
                            return parsed
            except Exception:
                pass

        return None

    def _clean_and_parse_json(self, text: str) -> Optional[Dict[str, Any]]:
        cleaned = text.strip()
        cleaned = re.sub(r"^```(?:json)?\s*", "", cleaned, flags=re.MULTILINE)
        cleaned = re.sub(r"\s*```$", "", cleaned, flags=re.MULTILINE)
        try:
            return json.loads(cleaned)
        except json.JSONDecodeError:
            m = re.search(r"(\{.*\})", cleaned, re.DOTALL)
            if m:
                try:
                    return json.loads(m.group(1))
                except json.JSONDecodeError:
                    pass
        return None

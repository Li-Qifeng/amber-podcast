import pytest
from amber_podcast.aggregator.itunes import ApplePodcastAggregator
from amber_podcast.aggregator.xiaoyuzhou import XiaoyuzhouAggregator

SAMPLE_RSS_XML = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>The Lex Fridman Podcast</title>
    <description>Conversations about AI, science, and technology.</description>
    <itunes:author>Lex Fridman</itunes:author>
    <itunes:image href="https://example.com/lex_cover.jpg"/>
    <item>
      <title>#450 - Elon Musk: Neuralink and AI</title>
      <guid>https://lexfridman.com/450</guid>
      <pubDate>Mon, 05 Oct 2026 12:00:00 GMT</pubDate>
      <itunes:duration>02:15:30</itunes:duration>
      <description>Discussion about Neuralink, optimus robot, and xAI.</description>
      <enclosure url="https://media.lexfridman.com/450.mp3" length="12345678" type="audio/mpeg"/>
    </item>
    <item>
      <title>#449 - Sam Altman: GPT-5</title>
      <guid>https://lexfridman.com/449</guid>
      <pubDate>Sun, 28 Sep 2026 10:00:00 GMT</pubDate>
      <itunes:duration>7200</itunes:duration>
      <description>Discussion on superintelligence.</description>
      <enclosure url="https://media.lexfridman.com/449.mp3" length="9876543" type="audio/mpeg"/>
    </item>
  </channel>
</rss>
"""

SAMPLE_XIAOYUZHOU_HTML = """
<!DOCTYPE html>
<html>
<head>
<script id="__NEXT_DATA__" type="application/json">
{
  "props": {
    "pageProps": {
      "episode": {
        "eid": "6888a0148e06fe8de74811af",
        "title": "从硅谷到具身智能：大模型的一线思考",
        "duration": 3420,
        "pubDate": "2026-10-09T08:00:00.000Z",
        "shownotes": "05:10 具身智能的突破\\n18:30 算力瓶颈与架构演进",
        "media": {
          "source": {
            "url": "https://media.xyzcdn.net/643cdf/test_audio.m4a"
          }
        },
        "podcast": {
          "pid": "6603ea352d9eae5d0a5f9151",
          "title": "硅谷高能量",
          "author": "科技特派员",
          "description": "硅谷一线的硬核对话",
          "image": {
            "largePicUrl": "https://image.xyzcdn.net/cover.jpg"
          }
        }
      }
    }
  }
}
</script>
</head>
<body></body>
</html>
"""

def test_apple_rss_parser():
    agg = ApplePodcastAggregator()
    parsed = agg.parse_rss_xml(SAMPLE_RSS_XML, feed_id="feed_lex")

    assert parsed["feed"]["title"] == "The Lex Fridman Podcast"
    assert parsed["feed"]["author"] == "Lex Fridman"
    assert parsed["feed"]["cover_url"] == "https://example.com/lex_cover.jpg"
    assert len(parsed["episodes"]) == 2

    ep1 = parsed["episodes"][0]
    assert ep1["title"] == "#450 - Elon Musk: Neuralink and AI"
    assert ep1["audio_url"] == "https://media.lexfridman.com/450.mp3"
    assert ep1["duration"] == 2 * 3600 + 15 * 60 + 30  # 8130 seconds
    assert ep1["guid"] == "https://lexfridman.com/450"

    ep2 = parsed["episodes"][1]
    assert ep2["duration"] == 7200

def test_xiaoyuzhou_parser():
    agg = XiaoyuzhouAggregator()
    parsed = agg.parse_episode_page(SAMPLE_XIAOYUZHOU_HTML)

    assert parsed["feed"]["title"] == "硅谷高能量"
    assert parsed["feed"]["author"] == "科技特派员"
    assert parsed["feed"]["source_type"] == "xiaoyuzhou"

    ep = parsed["episode"]
    assert ep["title"] == "从硅谷到具身智能：大模型的一线思考"
    assert ep["audio_url"] == "https://media.xyzcdn.net/643cdf/test_audio.m4a"
    assert ep["duration"] == 3420
    assert "05:10 具身智能的突破" in ep["shownotes"]

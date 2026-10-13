import SwiftUI

public struct ShownotesView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var selectedTab: Int = 0 // 0: Shownotes, 1: AI 精读长文

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Picker
            Picker("", selection: $selectedTab) {
                Text("原版 Shownotes").tag(0)
                Text("AI 深度精读笔记").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if selectedTab == 0 {
                        // Xiaoyuzhou-style parsed shownotes
                        if let episode = player.currentEpisode {
                            let parsedBlocks = parseTimestamps(from: episode.shownotes)
                            ForEach(parsedBlocks.indices, id: \.self) { idx in
                                let block = parsedBlocks[idx]
                                if let ts = block.timestampSec {
                                    // Clickable Timestamp Capsule (小宇宙风格)
                                    Button {
                                        player.seek(to: ts)
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "play.circle.fill")
                                                .font(.subheadline)
                                            Text(block.timeString)
                                                .font(.subheadline.bold().monospacedDigit())
                                            Text(block.text)
                                                .font(.subheadline)
                                                .foregroundStyle(.primary)
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text(block.text)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(5)
                                }
                            }
                        }
                    } else {
                        // AI Generated Article Notes
                        if player.articleMarkdown.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.largeTitle)
                                    .foregroundStyle(.secondary)
                                Text("该单集尚未生成精读笔记")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else {
                            Text(player.articleMarkdown)
                                .font(.body)
                                .lineSpacing(6)
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 60)
            }
        }
    }

    // MARK: - Timestamp Parser
    private struct ShownotesBlock {
        let text: String
        let timeString: String
        let timestampSec: Double?
    }

    private func parseTimestamps(from text: String) -> [ShownotesBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [ShownotesBlock] = []

        let regex = try? NSRegularExpression(pattern: @"(?:(\\d{1,2}):)?(\\d{2}):(\\d{2})", options: [])

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let nsString = trimmed as NSString
            let range = NSRange(location: 0, length: nsString.length)

            if let match = regex?.firstMatch(in: trimmed, options: [], range: range) {
                let timeStr = nsString.substring(with: match.range)
                let remainingText = nsString.substring(from: match.range.location + match.range.length).trimmingCharacters(in: .whitespaces)

                var totalSec: Double = 0
                let parts = timeStr.split(separator: ":").map { Double($0) ?? 0 }
                if parts.count == 3 {
                    totalSec = parts[0] * 3600 + parts[1] * 60 + parts[2]
                } else if parts.count == 2 {
                    totalSec = parts[0] * 60 + parts[1]
                }

                blocks.append(ShownotesBlock(
                    text: remainingText,
                    timeString: timeStr,
                    timestampSec: totalSec
                ))
            } else {
                blocks.append(ShownotesBlock(
                    text: trimmed,
                    timeString: "",
                    timestampSec: nil
                ))
            }
        }
        return blocks
    }
}

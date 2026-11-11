import SwiftUI

public struct ShownotesView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var selectedTab: Int = 0 // 0: Shownotes, 1: AI 深度精读笔记
    @Namespace private var tabNamespace
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Segmented Tab Switcher
            AmberGlassContainer(spacing: 6) {
                HStack(spacing: 4) {
                    tabButton(title: "原版节目单", tag: 0)
                    tabButton(title: "精读笔记", tag: 1, icon: "doc.text")
                }
                .padding(3)
                .amberGlass(.capsule, isInteractive: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if selectedTab == 0 {
                        // Xiaoyuzhou-style parsed shownotes with timestamp air drops
                        if let episode = player.currentEpisode,
                           !episode.shownotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let parsedBlocks = parseTimestamps(from: episode.shownotes)
                            if parsedBlocks.isEmpty {
                                emptyShownotesView
                            } else {
                                ForEach(parsedBlocks.indices, id: \.self) { idx in
                                    let block = parsedBlocks[idx]
                                    if let ts = block.timestampSec {
                                        // Clickable Timestamp Capsule (Xiaoyuzhou / Forward Style)
                                        Button {
                                            impactFeedback.impactOccurred()
                                            player.seek(to: ts)
                                        } label: {
                                            HStack(spacing: 8) {
                                                Image(systemName: "play.fill")
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(AmberTheme.primaryAmber)

                                                Text(block.timeString)
                                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                    .foregroundStyle(AmberTheme.primaryAmber)

                                                Text(block.text.isEmpty ? "跳转至此时间点" : block.text)
                                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                                    .foregroundStyle(AmberTheme.labelPrimary)
                                                    .lineLimit(2)

                                                Spacer()

                                                Image(systemName: "chevron.right")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .foregroundStyle(AmberTheme.labelTertiary)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .amberPlate(radius: 10)
                                        }
                                        .buttonStyle(.plain)
                                        .amberPressable(scale: 0.98)
                                    } else {
                                        Text(block.text)
                                            .font(.system(size: 14.5, weight: .regular))
                                            .foregroundStyle(AmberTheme.labelSecondary)
                                            .lineSpacing(6)
                                    }
                                }
                            }
                        } else {
                            emptyShownotesView
                        }
                    } else {
                        // AI Generated Article Notes with Apple Books Editorial Typography
                        if player.articleMarkdown.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 36, weight: .thin))
                                    .foregroundStyle(AmberTheme.labelTertiary)

                                Text("该单集尚未生成精读笔记")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(AmberTheme.labelSecondary)

                                Text("单集完成双轨转译后，将在此生成全文脉络、金句摘录与概念详解。")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(AmberTheme.labelTertiary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 50)
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                // Editorial Header Tag
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.plaintext")
                                        .font(.system(size: 10, weight: .medium))
                                    Text("全文脉络精读")
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                }
                                .foregroundStyle(AmberTheme.primaryAmber)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(AmberTheme.primaryAmber.opacity(0.12), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

                                Text(player.articleMarkdown)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(AmberTheme.labelPrimary)
                                    .lineSpacing(7)
                                    .textSelection(.enabled)
                            }
                            .padding(18)
                            .amberPlate(radius: AmberTheme.radiusCardRow)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 60)
            }
        }
    }

    private var emptyShownotesView: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 36, weight: .thin))
                .foregroundStyle(AmberTheme.labelTertiary)

            Text("暂无节目单内容")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AmberTheme.labelSecondary)

            Text("发布者未随音频附带 Shownotes 信息。")
                .font(.system(size: 12.5))
                .foregroundStyle(AmberTheme.labelTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private func tabButton(title: String, tag: Int, icon: String? = nil) -> some View {
        let isSelected = selectedTab == tag
        return Button {
            impactFeedback.impactOccurred()
            withAnimation(AmberTheme.quickSpring) {
                selectedTab = tag
            }
        } label: {
            HStack(spacing: 5) {
                if let ic = icon {
                    Image(systemName: ic)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 12.5, weight: isSelected ? .bold : .medium, design: .rounded))
            }
            .foregroundStyle(isSelected ? AmberTheme.labelPrimary : AmberTheme.labelSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(
                Group {
                    if isSelected {
                        Capsule()
                            .fill(Color.white.opacity(0.16))
                            .matchedGeometryEffect(id: "ShownotesTabCapsule", in: tabNamespace)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Timestamp Parser
    private struct ShownotesBlock {
        let text: String
        let timeString: String
        let timestampSec: Double?
    }

    private func cleanHtml(_ raw: String) -> String {
        var text = raw
        // Replace paragraph and break tags with newlines
        text = text.replacingOccurrences(of: #"(?i)<(?:br|/p|/div|/li)\s*/?>"#, with: "\n", options: .regularExpression)
        // Strip remaining HTML tags
        text = text.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
        // Decode common HTML entities
        let entities = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&hellip;", "…")
        ]
        for (ent, val) in entities {
            text = text.replacingOccurrences(of: ent, with: val)
        }
        return text
    }

    private func parseTimestamps(from rawText: String) -> [ShownotesBlock] {
        let cleanText = cleanHtml(rawText)
        let lines = cleanText.components(separatedBy: .newlines)
        var blocks: [ShownotesBlock] = []

        let regex = try? NSRegularExpression(pattern: #"(?:(\d{1,2}):)?(\d{2}):(\d{2})"#, options: [])

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let nsString = trimmed as NSString
            let range = NSRange(location: 0, length: nsString.length)

            if let match = regex?.firstMatch(in: trimmed, options: [], range: range) {
                let timeStr = nsString.substring(with: match.range)
                let prefix = nsString.substring(to: match.range.location).trimmingCharacters(in: .whitespaces)
                let suffix = nsString.substring(from: match.range.location + match.range.length).trimmingCharacters(in: .whitespaces)
                let combined = prefix.isEmpty ? suffix : (suffix.isEmpty ? prefix : "\(prefix) \(suffix)")
                let cleanBlockText = combined.trimmingCharacters(in: CharacterSet(charactersIn: " -—:·|[]()"))

                var totalSec: Double = 0
                let parts = timeStr.split(separator: ":").map { Double($0) ?? 0 }
                if parts.count == 3 {
                    totalSec = parts[0] * 3600 + parts[1] * 60 + parts[2]
                } else if parts.count == 2 {
                    totalSec = parts[0] * 60 + parts[1]
                }

                blocks.append(ShownotesBlock(
                    text: cleanBlockText.isEmpty ? "跳转至 \(timeStr)" : cleanBlockText,
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

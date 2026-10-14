import SwiftUI

public struct ShownotesView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var selectedTab: Int = 0 // 0: Shownotes, 1: AI 深度精读笔记
    @Namespace private var tabNamespace
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Forward-style Pill Tab Switcher
            HStack(spacing: 4) {
                tabButton(title: "原版 Shownotes", tag: 0)
                tabButton(title: "AI 深度精读笔记", tag: 1, icon: "sparkles")
            }
            .padding(3)
            .liquidGlassCapsule()
            .padding(.horizontal, 24)
            .padding(.top, 10)
            .padding(.bottom, 16)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    if selectedTab == 0 {
                        // Xiaoyuzhou-style parsed shownotes with timestamp air drops
                        if let episode = player.currentEpisode {
                            let parsedBlocks = parseTimestamps(from: episode.shownotes)
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

                                            Text(block.text)
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
                                        .liquidGlassCard(cornerRadius: 12)
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
                        // AI Generated Article Notes with Apple Books Editorial Typography
                        if player.articleMarkdown.isEmpty {
                            VStack(spacing: 14) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 40))
                                    .foregroundStyle(AmberTheme.primaryAmber.opacity(0.6))

                                Text("该单集尚未生成精读笔记")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(AmberTheme.labelSecondary)

                                Text("单集完成 AI 双轨转译后，将在此自动生成全文脉络、金句摘录与概念详解。")
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
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 11))
                                    Text("AI 全文脉络精读")
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                }
                                .foregroundStyle(AmberTheme.primaryAmber)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AmberTheme.primaryAmber.opacity(0.12), in: Capsule())

                                Text(player.articleMarkdown)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundStyle(AmberTheme.labelPrimary)
                                    .lineSpacing(7)
                                    .textSelection(.enabled)
                            }
                            .padding(18)
                            .liquidGlassCard(cornerRadius: 18)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 60)
            }
        }
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

    private func parseTimestamps(from text: String) -> [ShownotesBlock] {
        let lines = text.components(separatedBy: .newlines)
        var blocks: [ShownotesBlock] = []

        let regex = try? NSRegularExpression(pattern: #"(?:(\d{1,2}):)?(\d{2}):(\d{2})"#, options: [])

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

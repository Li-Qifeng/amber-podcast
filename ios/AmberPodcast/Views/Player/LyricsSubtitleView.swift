import SwiftUI

public struct LyricsSubtitleView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var autoScroll: Bool = true

    public init() {}

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(player.fullMapping) { seg in
                        let isCurrent = seg.index == player.currentSegmentIndex

                        VStack(alignment: .leading, spacing: 8) {
                            // Speaker tag
                            HStack {
                                Text(seg.speaker)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.ultraThinMaterial, in: Capsule())

                                Spacer()

                                Text(formatSeconds(seg.enRange.start))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                            }

                            // Primary Display Text based on mode
                            if player.trackMode == .chinese {
                                Text(seg.zhDisplay)
                                    .font(.system(size: isCurrent ? 24 : 19, weight: isCurrent ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(isCurrent ? Color.primary : Color.secondary.opacity(0.6))
                                    .lineSpacing(4)
                                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isCurrent)

                                // Subordinate original text
                                Text(seg.enText)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(.secondary.opacity(isCurrent ? 0.8 : 0.4))
                            } else {
                                Text(seg.enText)
                                    .font(.system(size: isCurrent ? 24 : 19, weight: isCurrent ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(isCurrent ? Color.primary : Color.secondary.opacity(0.6))
                                    .lineSpacing(4)
                                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isCurrent)

                                Text(seg.zhDisplay)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(.secondary.opacity(isCurrent ? 0.8 : 0.4))
                            }
                        }
                        .id(seg.index)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            let targetTime = (player.trackMode == .chinese) ? seg.zhRange.start : seg.enRange.start
                            player.seek(to: targetTime)
                        }
                        .scaleEffect(isCurrent ? 1.02 : 1.0, anchor: .leading)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isCurrent)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 40)
            }
            .onChange(of: player.currentSegmentIndex) { newIndex in
                if autoScroll {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
    }

    private func formatSeconds(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

import SwiftUI

public struct LyricsSubtitleView: View {
    @ObservedObject var player = DualTrackAudioPlayer.shared
    @State private var autoScroll: Bool = true
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {}

    public var body: some View {
        if player.fullMapping.isEmpty {
            VStack(spacing: 14) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(AmberTheme.labelTertiary)

                Text("暂无双轨逐句字幕")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)

                Text("当前单集尚未生成双轨逐句对齐，可在单集卡片中发起生成。")
                    .font(.system(size: 12.5))
                    .foregroundStyle(AmberTheme.labelTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 32) {
                    Color.clear.frame(height: 24)

                    ForEach(player.fullMapping) { seg in
                        SubtitleSegmentRow(
                            seg: seg,
                            currentSegmentIndex: player.currentSegmentIndex,
                            trackMode: player.trackMode,
                            onTap: {
                                impactFeedback.impactOccurred()
                                let targetTime = (player.trackMode == .chinese) ? seg.zhRange.start : seg.enRange.start
                                player.seek(to: targetTime)
                            }
                        )
                    }

                    Color.clear.frame(height: 80)
                }
                .padding(.horizontal, 28)
            }
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 36)
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 60)
                }
            )
            .onChange(of: player.currentSegmentIndex) { newIndex in
                if autoScroll {
                    withAnimation(AmberTheme.fluidSpring) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
            }
        }
        }
    }
}

// MARK: - Subtitle Segment Row (Decoupled for instantaneous Swift compiler type-checking)
private struct SubtitleSegmentRow: View {
    let seg: FullMappingSegment
    let currentSegmentIndex: Int
    let trackMode: TrackMode
    let onTap: () -> Void

    private var isCurrent: Bool {
        seg.index == currentSegmentIndex
    }

    private var distance: Int {
        abs(seg.index - currentSegmentIndex)
    }

    private var secondaryOpacity: Double {
        max(0.18, 0.55 - Double(distance) * 0.12)
    }

    private var blurRadius: CGFloat {
        isCurrent ? 0 : min(1.8, CGFloat(distance) * 0.45)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Speaker & Timestamp Tag
            HStack(spacing: 8) {
                Text(seg.speaker)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isCurrent ? AmberTheme.primaryAmber : AmberTheme.labelTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(isCurrent ? AmberTheme.primaryAmber.opacity(0.12) : AmberTheme.surfaceRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(isCurrent ? AmberTheme.primaryAmber.opacity(0.25) : AmberTheme.borderHairline, lineWidth: 0.5)
                    )

                Text(formatSeconds(trackMode == .chinese ? seg.zhRange.start : seg.enRange.start))
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(AmberTheme.labelTertiary)

                Spacer()
            }

            // Primary Subtitle Typography
            if trackMode == .chinese {
                Text(seg.zhDisplay)
                    .font(.system(size: isCurrent ? 25 : 19, weight: isCurrent ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isCurrent ? AmberTheme.labelPrimary : AmberTheme.labelSecondary.opacity(secondaryOpacity))
                    .lineSpacing(6)
                    .blur(radius: blurRadius)
                    .scaleEffect(isCurrent ? 1.02 : 1.0, anchor: .leading)
                    .animation(AmberTheme.fluidSpring, value: isCurrent)

                Text(seg.enText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AmberTheme.labelTertiary.opacity(isCurrent ? 0.75 : 0.3))
                    .lineSpacing(3)
            } else {
                Text(seg.enText)
                    .font(.system(size: isCurrent ? 25 : 19, weight: isCurrent ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isCurrent ? AmberTheme.labelPrimary : AmberTheme.labelSecondary.opacity(secondaryOpacity))
                    .lineSpacing(6)
                    .blur(radius: blurRadius)
                    .scaleEffect(isCurrent ? 1.02 : 1.0, anchor: .leading)
                    .animation(AmberTheme.fluidSpring, value: isCurrent)

                Text(seg.zhDisplay)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AmberTheme.labelTertiary.opacity(isCurrent ? 0.75 : 0.3))
                    .lineSpacing(3)
            }
        }
        .id(seg.index)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }

    private func formatSeconds(_ seconds: Double) -> String {
        guard !seconds.isNaN && seconds >= 0 else { return "00:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

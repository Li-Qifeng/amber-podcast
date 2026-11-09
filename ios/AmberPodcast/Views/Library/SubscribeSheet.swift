import SwiftUI

public struct SubscribeSheet: View {
    public var onSubscribed: ((PodcastFeed) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var newUrlInput: String = ""
    @State private var autoTranslateNew: Bool = true
    @State private var isSubscribing: Bool = false
    @State private var errorMessage: String? = nil
    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    public init(onSubscribed: ((PodcastFeed) -> Void)? = nil) {
        self.onSubscribed = onSubscribed
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                AmberTheme.background.ignoresSafeArea()

                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("RSS 订阅源或播客 URL")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AmberTheme.labelSecondary)

                        TextField("粘贴 Apple Podcasts / 小宇宙链接", text: $newUrlInput)
                            .font(.system(size: 14))
                            .padding(12)
                            .background(AmberTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(AmberTheme.borderHairline, lineWidth: 0.5)
                            )
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自动生成中文译制与字幕")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AmberTheme.labelPrimary)
                            Text("外语播客自动配音译制，中文播客极速识别原声打轴")
                                .font(.system(size: 11.5))
                                .foregroundStyle(AmberTheme.labelTertiary)
                        }
                        Spacer()
                        Toggle("", isOn: $autoTranslateNew)
                            .labelsHidden()
                            .tint(AmberTheme.primaryAmber)
                    }
                    .padding(12)
                    .background(AmberTheme.surfaceCard, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    if let err = errorMessage {
                        Text(err)
                            .font(.system(size: 12))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()

                    Button {
                        subscribeAction()
                    } label: {
                        HStack(spacing: 6) {
                            if isSubscribing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isSubscribing ? "正在解析并订阅..." : "确认添加订阅")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            newUrlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.white.opacity(0.3)
                                : Color.white,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                    }
                    .disabled(newUrlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubscribing)
                }
                .padding(20)
            }
            .navigationTitle("添加播客")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundStyle(AmberTheme.labelSecondary)
                }
            }
        }
    }

    private func subscribeAction() {
        let trimmed = newUrlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSubscribing = true
        errorMessage = nil
        impactFeedback.impactOccurred()

        Task {
            do {
                let feed = try await LibraryStore.shared.subscribe(url: trimmed, autoTranslate: autoTranslateNew)
                await MainActor.run {
                    self.isSubscribing = false
                    self.onSubscribed?(feed)
                    self.dismiss()
                }
            } catch {
                await MainActor.run {
                    self.isSubscribing = false
                    self.errorMessage = "订阅失败: \(error.localizedDescription)"
                }
            }
        }
    }
}

import SwiftUI

public struct PipelineStatusView: View {
    @StateObject private var apiClient = AmberAPIClient.shared
    @State private var statusData: AmberAPIClient.PipelineStatusResponse? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showSettingsSheet: Bool = false

    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AmberTheme.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        // 1. Status Telemetry Cards Grid
                        telemetryCardsSection

                        // 2. Active Transcription / Dump Tasks Queue
                        activeTasksSection

                        // 3. Recently Completed Archives
                        completedTasksSection

                        // 4. Engine & Infrastructure Info
                        infrastructureSection

                        // Bottom clearance for floating Dock & MiniPlayer
                        Color.clear.frame(height: 168)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }
                .refreshable {
                    await loadStatus()
                }
            }
            .navigationTitle("后台转储")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        impactFeedback.impactOccurred()
                        showSettingsSheet = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(AmberTheme.labelSecondary)
                            .padding(8)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                SettingsView()
            }
            .task {
                await loadStatus()
            }
        }
    }

    // MARK: - 1. Telemetry Cards Section
    private var telemetryCardsSection: some View {
        let summary = statusData?.summary
        let activeCount = summary?.activeCount ?? 0
        let readyCount = summary?.readyCount ?? 0
        let storageMb = summary?.storageMb ?? 0.0

        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            // Card 1: Active Tasks
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(activeCount > 0 ? AmberTheme.primaryAmber : AmberTheme.labelTertiary)
                    Spacer()
                    if activeCount > 0 {
                        Circle()
                            .fill(AmberTheme.primaryAmber)
                            .frame(width: 8, height: 8)
                    }
                }
                Text("\(activeCount)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                Text("进行中转写任务")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AmberTheme.labelSecondary)
            }
            .padding(14)
            .amberPlate(radius: 14)

            // Card 2: Ready Archives
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AmberTheme.accentElectric)
                    Spacer()
                    Text("双轨已就绪")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(AmberTheme.accentElectric)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AmberTheme.accentElectric.opacity(0.12), in: Capsule())
                }
                Text("\(readyCount)")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                Text("已转储归档单集")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AmberTheme.labelSecondary)
            }
            .padding(14)
            .amberPlate(radius: 14)

            // Card 3: Storage Used
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "internaldrive.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.cyan)
                    Spacer()
                }
                Text(String(format: "%.1f MB", storageMb))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                Text("转储存储占用")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AmberTheme.labelSecondary)
            }
            .padding(14)
            .amberPlate(radius: 14)

            // Card 4: ASR Engine Status
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "cpu.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AmberTheme.primaryAmber)
                    Spacer()
                    Text("在线")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15), in: Capsule())
                }
                Text("SenseNova")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                    .lineLimit(1)
                Text("ASR 语音模型")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AmberTheme.labelSecondary)
            }
            .padding(14)
            .amberPlate(radius: 14)
        }
    }

    // MARK: - 2. Active Tasks Section
    private var activeTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("正在转储与转写")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AmberTheme.labelPrimary)
                Spacer()
                if let tasks = statusData?.activeTasks, !tasks.isEmpty {
                    Text("\(tasks.count) 个任务")
                        .font(.system(size: 11.5))
                        .foregroundStyle(AmberTheme.primaryAmber)
                }
            }

            if let tasks = statusData?.activeTasks, !tasks.isEmpty {
                ForEach(tasks) { task in
                    activeTaskCard(task)
                }
            } else {
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20))
                        .foregroundStyle(AmberTheme.labelTertiary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("当前无后台转写任务")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AmberTheme.labelPrimary)
                        Text("在单集详情中点击“AI 双语精译”或订阅新播客，即可排队处理。")
                            .font(.system(size: 11))
                            .foregroundStyle(AmberTheme.labelTertiary)
                    }
                    Spacer()
                }
                .padding(16)
                .amberPlate(radius: 12)
            }
        }
    }

    private func activeTaskCard(_ task: Episode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(AmberTheme.labelPrimary)
                        .lineLimit(1)
                    Text(task.statusDescription)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AmberTheme.primaryAmber)
                }
                Spacer()
                Text("\(task.progress)%")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AmberTheme.primaryAmber)
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AmberTheme.primaryAmber)
                        .frame(width: max(0, min(geo.size.width * CGFloat(task.progress) / 100.0, geo.size.width)), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .amberPlate(radius: 12)
    }

    // MARK: - 3. Completed Tasks Section
    private var completedTasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近完成归档")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AmberTheme.labelPrimary)

            if let recent = statusData?.recentCompleted, !recent.isEmpty {
                ForEach(recent) { ep in
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(AmberTheme.accentElectric)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(ep.title)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(AmberTheme.labelPrimary)
                                .lineLimit(1)
                            Text(ep.durationFormatted)
                                .font(.system(size: 11))
                                .foregroundStyle(AmberTheme.labelTertiary)
                        }

                        Spacer()

                        Text("双轨已生成")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(AmberTheme.labelSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Color.white.opacity(0.06), in: Capsule())
                    }
                    .padding(12)
                    .amberPlate(radius: 10)
                }
            } else {
                Text("暂无归档记录")
                    .font(.system(size: 12))
                    .foregroundStyle(AmberTheme.labelTertiary)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - 4. Infrastructure Section
    private var infrastructureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("流水线架构状态")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AmberTheme.labelPrimary)

            VStack(spacing: 0) {
                infraRow(title: "语音识别 (ASR)", value: statusData?.summary.asrEngine ?? "SenseNova / Whisper", icon: "waveform")
                Divider().background(Color.white.opacity(0.06))
                infraRow(title: "双语精译模型", value: "SenseNova / OpenAI GPT-4o", icon: "character.book.closed.fill")
                Divider().background(Color.white.opacity(0.06))
                infraRow(title: "语音克隆 (TTS)", value: statusData?.summary.ttsEngine ?? "Edge Dual-Track", icon: "speaker.wave.2.fill")
                Divider().background(Color.white.opacity(0.06))
                infraRow(title: "网关健康度", value: statusData?.summary.serverStatus == "healthy" ? "正常运行 (200 OK)" : "连接检查中", icon: "network")
            }
            .amberPlate(radius: 12)
        }
    }

    private func infraRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(AmberTheme.labelSecondary)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(AmberTheme.labelSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AmberTheme.labelPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Actions
    private func loadStatus() async {
        isLoading = true
        do {
            let res = try await apiClient.fetchPipelineStatus()
            await MainActor.run {
                self.statusData = res
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

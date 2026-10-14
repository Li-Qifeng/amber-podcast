# Amber 播客 iOS 前端从零重构实现计划 (Superpowers SDD)

> **For Hermes:** 采用 Superpowers `subagent-driven-development` 规范，通过 `delegate_task` 派发子代理分模块重写，严格遵循 2-Stage Review（规范符合度审 + 代码质量审）。

**Goal:** 基于 Forward / Rex 像素级比例研究文档与 Apple Fluid / Liquid Glass 设计语言，全面重写 Amber 播客客户端的前端视图与设计系统，提供如 Apple 官方般丝滑沉浸的双轨播客体验。

**Architecture:** 
1. `AmberDesignSystem.swift`: 统领视觉语义 Token（Liquid Glass 次表面散射材质、0.75pt 菲涅尔高光边缘、Concentric Squircle 圆角体系、ForwardMotion 弹簧动力学）。
2. `HomeLibraryView.swift`: 61.8% 霸屏 Hero 流体视窗 + 16:9 宽屏流体卡片滑轨（Peek 35%）+ 2:3 纵向海报流。
3. `MainTabView.swift` & `MiniPlayerView.swift`: 91% 屏宽悬浮双胶囊岛（Liquid Glass Dock + MiniPlayer），距底 32pt 避让 Home Indicator。
4. `FullPlayerView.swift` & `LyricsSubtitleView.swift` & `ShownotesView.swift`: 呼吸封面物理反馈 + 解耦高帧率 Apple Music 级虚化歌词 + 结构化精读 Shownotes。
5. `FeedDetailView.swift` & `SearchView.swift` & `SettingsView.swift`: 统一液态玻璃卡片底衬与触觉按压反馈。

**Tech Stack:** SwiftUI, AVFoundation, Combine, iOS 17+, XcodeGen.

---

### Task 1: 规范级 Design Tokens 与 Liquid Glass 基础修饰符
- **Files:** `/root/projects/amber-podcast/ios/AmberPodcast/Services/AmberDesignSystem.swift`
- **目标:** 固化 Liquid Glass 次表面散射材质、0.75pt 菲涅尔高光、Concentric Squircle 半径、触觉按压修饰符与 ForwardMotion 物理弹簧参数。

### Task 2: 首页骨架重构 (61.8% Hero + 16:9 Shelf Cards + 2:3 海报滑轨)
- **Files:** `/root/projects/amber-podcast/ios/AmberPodcast/Views/Library/HomeLibraryView.swift`
- **目标:** 彻底推翻电商货架两列网格，以 61.8% 沉浸封面为视觉焦点，下方承接 16:9 横滑探索卡片与 2:3 海报流。

### Task 3: 悬浮双胶囊岛系统 (MainTabView & MiniPlayerView)
- **Files:** 
  - `/root/projects/amber-podcast/ios/AmberPodcast/Views/MainTabView.swift`
  - `/root/projects/amber-podcast/ios/AmberPodcast/Views/Player/MiniPlayerView.swift`
- **目标:** 91% 屏宽、高度 58pt、悬浮于屏幕底部 32pt 的 Liquid Glass Dock，以及优雅悬浮其上方的 MiniPlayer 胶囊。

### Task 4: 播放器核心矩阵 (FullPlayerView, LyricsSubtitleView, ShownotesView)
- **Files:**
  - `/root/projects/amber-podcast/ios/AmberPodcast/Views/Player/FullPlayerView.swift`
  - `/root/projects/amber-podcast/ios/AmberPodcast/Views/Player/LyricsSubtitleView.swift`
  - `/root/projects/amber-podcast/ios/AmberPodcast/Views/Player/ShownotesView.swift`
- **目标:** 封面呼吸物理缩放、独立解耦 SubtitleSegmentRow（规避 Swift 编译超时）双轨字幕虚化、液态玻璃胶囊 Shownotes。

### Task 5: 详情、搜索与设置视图风格对齐
- **Files:**
  - `/root/projects/amber-podcast/ios/AmberPodcast/Views/Library/FeedDetailView.swift`
  - `/root/projects/amber-podcast/ios/AmberPodcast/Views/Library/EpisodeRowView.swift`
  - `/root/projects/amber-podcast/ios/AmberPodcast/Views/Search/SearchView.swift`
  - `/root/projects/amber-podcast/ios/AmberPodcast/Views/Settings/SettingsView.swift`
- **目标:** 彻底清除旧版粗糙边框与死板背景，全面换装 Liquid Glass 风格卡片与药丸标签。

### Task 6: 编译、打包、签名与 AirStore 上架验证
- **验证:** Git Push → GitHub Actions Xcode 16.1 编译 IPA → zsign 重签名注入 → AirStore Studio 更新 → 交付真机下载。

# Changelog

## Qstats [1.7.0] - 2026-10-10

- **状态栏网络速率单行合并与零抖动定宽槽位**：
  - 将原独立的上传与下载两行合并为单行展示（`↓ 下载   ↑ 上传`），缩减纵向菜单占用。
  - 引入等宽字符定宽槽位（10 字符右对齐），配合菜单宽度最小约束 `220pt`，彻底根除高流量波动导致的下拉菜单宽度横向抖动。
- **全局快捷键增强与全量纳管**：
  - 新增全局「剪贴板贴图」快捷键（默认 `⌥V`），支持与「区域截图」快捷键一同在偏好设置中自定义与恢复默认。
  - 状态栏主菜单中「区域截图」与「剪贴板贴图」右侧原生渲染快捷键提示符号（与「设置」、「退出」保持一致对齐排版）。
- **偏好设置架构升级与主菜单极简瘦身**：
  - 将原分散在主菜单中的「快捷键设置」、「菜单栏显示」与「显示样式」子菜单全量整合入现代化设置面板（卡片流排版与实时双向同步）。
  - 主菜单文案规范化：去除非模态操作的省略号，文案收敛为「设置」与「退出」。
  - 「检查更新」移入「关于」面板，提供主从双按钮对称交互与请求防抖。

## Qstats [1.6.0] - 2026-10-10

- **系统开机自启（Launch at Login）**：
  - 基于 macOS 13+ 原生 `ServiceManagement.SMAppService.mainApp` 架构实现，免辅助进程注入，系统级原生可靠调度。
  - 具备异常捕获与状态实时回滚保护，支持开机登录自动静默启动。
- **现代化偏好设置独立面板（Settings Window）**：
  - 遵循 Apple HIG 采用毛玻璃（HUD VisualEffect）卡片化排版。
  - 采用系统原生 `NSSwitch` 触控开关分别控制「开机自启动」与「屏幕录制权限」。
  - 动态监听系统前后台激活通知，从系统设置修改隐私授权切回应用即刻自动感知并同步开关状态与状态徽章。
  - 提供快捷「系统设置」与「重启应用」引导入口，极大简化首次授权流程。
- **状态栏菜单与界面视觉精简重构**：
  - 移除下拉菜单顶部的 `Qstats v1.5.0` 品牌标题行与分割线，顶部直接紧凑展示实时流速等监控数据。
  - 菜单底部新增「设置…」入口（绑定快捷键 `⌘,`），并将「关于 Qstats」简化为「关于」。
  - 全面重构「关于」面板：移除生硬的浅绿大药丸徽标与陈旧胶囊标签，优化图标柔和环境光阴影，采用 Apple 原生标准 Typography 与紧凑布局，隐藏多余交通灯，支持 `Esc` 一键关闭。

## Qstats [1.5.0] - 2026-09-22

- **截图取色放大镜（Loupe & Pixel Inspector）**：
  - 新增 $17 \times 17$ 物理像素最近邻（Nearest-Neighbor）无损插值高倍放大视窗，呈现刀锋般清晰的像素网格。
  - 荧光绿准星精准贯穿瞄准物理像素，卡片面板等宽实时呈现光标绝对物理坐标（如 `1042, 1314`）与十六进制色值（`#RRGGBB`）。
  - 支持快捷键 `⌘+C` 或单键 `C` 复制当前色值到剪贴板，带有专属复制动效与成功反馈。
  - 集成智能贴边防遮挡翻转算法与事件完全穿透设计，拉框框选截图时自动静默隐藏。
- **桌面贴图（Pinned Screenshot）重大体验与稳定性修复**：
  - **修复滚轮缩放失效及背景滚动条泄漏**：派生 `PinnedPanel` 解决无边框浮窗非 Key 状态输入接管问题，兼容高精触摸板与普通鼠标滚轮，彻底消除事件透传引起的底层应用滚动条弹出现象。
  - **修复四角拖拽剧烈抖动**：禁用系统背景拖动机制，采用严格对角线正交投影数学算法，实现单向连续、无死锁且绝对平滑的等比缩放。
  - **四角 Hover 光标与手柄高亮**：补齐四角高对比度微晶指示器并在鼠标悬停时激活青绿色手柄高亮与圆点反馈；内嵌关闭按钮避让手柄热区，支持 `Esc` 退出与 `⌘+C` 快速复制。

## Qstats [1.4.0] - 2026-09-22

- **版本更新检测双通道容灾架构（Dual-Channel Fallback）**：
  - 新增 `raw.githubusercontent.com` 静态源 Fallback 容灾通道，当 GitHub REST API 遭遇匿名单 IP 60 次/小时频控限制（HTTP 403 Rate Limit）时，自动无缝降级进行版本核对，彻底根除检查更新报错。
  - 优化更新提示与版本跳转交互，支持一键前往 GitHub Releases 获取最新安装包。

## Qstats [1.3.0] - 2026-09-22

- **展开菜单无缝截图架构（Seamless Overlay）**：
  - 采用主线程直接同步采集物理屏幕帧缓冲区（$<8\text{ms}$），并在 `.screenSaver` 层级（Level 1000）即时无感覆盖全屏快照，彻底解决展开状态栏下拉菜单时无法截图及菜单关闭后连环闪烁问题。
  - 展开中的菜单画面在截图时得以 $100\%$ 完美定格并保留在底图画面中，视觉零闪烁、零延迟。
  - 精简下拉菜单布局与数值排版，将指标制表位由 160pt 紧凑至 120pt，限制菜单最小宽度，整体界面更紧凑美观。
- **贴图交互全方位重构**：
  - 重写桌面贴图窗口缩放算法为绝对对角锚点距离公式（Direct Opposite-Anchor Manipulation），彻底修复缩小后“无论是放大还是缩小都变成缩小”的手势计算缺陷。
  - 原生支持 macOS 触摸板双指捏合（Pinch-to-zoom / `magnify`）平滑缩放。
  - 增强鼠标滚轮与触摸板双指滑动的死区过滤与平滑因数，保证任何缩放操作严格锁定图片原始宽高比（Aspect Ratio）。
- **截图工具栏与马赛克增强**：
  - 工具栏最右侧集成系统 SF Symbol `checkmark` 确认按钮，绑定回车完成截图逻辑。
  - 马赛克升级为交互实体：支持 4 角拉动手柄放大缩小、内部按住拖拽平移、滑块动态调节模糊度、Delete 键与微型删除按钮即时移除及纯净无痕导出。

## Qstats [1.2.0] - 2026-09-21

- Change the default region screenshot shortcut to Option-D.
- Add a native shortcut recorder, persistent custom shortcuts, conflict detection and one-click reset.
- Replace the flat text-entry field with a compact glass editor and smaller placeholder text.
- Add distinct high-contrast cursors for selection and every annotation tool.
- Add hover, pressed and selected feedback to all screenshot toolbar buttons.
- Fix the Save PNG action appearing to freeze by presenting the save panel asynchronously above the capture overlay.
- Continue shipping exactly two macOS installers: Apple Silicon and Intel.

## Qstats [1.1.0] - 2026-09-21

- Add on-demand multi-display region screenshots with a global Control-Shift-2 shortcut.
- Add a compact native annotation toolbar with rectangles, arrows, pen, mosaic, text, colors, widths and undo.
- Add PNG copy/save, screenshot pinning and clipboard image pinning.
- Add draggable always-on-top image windows with zoom and opacity controls.
- Keep screen access isolated from the continuously running system monitors.
- Build and validate separate Apple Silicon and Intel DMG installers.
- Document the screenshot architecture, privacy behavior and release plan.

## Qstats [1.0.0] - 2026-09-21

- Rename the application, executable, bundle and distribution files to `Qstats`.
- Replace the wordmark icon with a minimal, text-free activity pulse.
- Add persistent, immediate menu-bar selection for any 1–4 metrics (all enabled by default).
- Add per-metric ring, horizontal bar, vertical bar and percentage text menu controls.
- Refine spacing, ring weight, rounded tracks and two-row network typography.
- Preserve an entry point when GPU data is unavailable or a config hides every metric.
- Migrate legacy preferences and preserve advanced YAML settings when saving selections.
- Add macOS CI tests, style preview renders and Universal DMG/ZIP packaging.
- Publish new versions to GitHub Releases after successful main builds, preserving existing releases.
- Reset this fork's version to 1.0.0; prior upstream releases are retained below for attribution.

## Upstream history — OSX Stats Nano

## [1.0.10] - 2026-04-06

### Fix: remove unnecessary StatusBarController recreation on wake

**Symptom observed (Apr 6 2026):**
After connecting an external monitor and rearranging displays, the system log showed
recurring `[BSBlockSentinel:FBSWorkspaceScenesClient] failed!` errors from the BaseBoard
framework. These appeared immediately after the display reconfiguration event and then
continued at ~10-minute intervals, suggesting the ControlCenter scene for the status bar
item was failing to reconnect after being torn down.

**Root cause analysis:**
`systemDidWake` was recreating the entire `StatusBarController` (and therefore a new
`NSStatusItem`) on every wake. The original justification (PR #2, Mar 28 2026) was that
"NSStatusItem can become invalid after a long overnight sleep". However:

1. On modern macOS, `NSStatusItem` is retained and managed by ControlCenter across
   sleep/wake cycles — it does not become invalid.
2. The actual post-sleep crash (PR #3, Apr 3 2026) was caused by `NetworkMonitor`'s stale
   `previousTime` causing a UInt64 overflow, and was already fixed by calling `reset()` in
   `StatsPoller.start()`.
3. Recreating `NSStatusItem` during an already-unstable window (display reconfiguration,
   system wake) tears down the active ControlCenter scene and requests a new one, which
   times out → `BSBlockSentinel` failures.

**Hypothesis:**
The `StatusBarController` recreation was never necessary and was masking the real fix
(monitor state reset). Removing it eliminates the scene churn and the `BSBlockSentinel`
errors. If the status bar item ever genuinely disappears after a long sleep in a future
macOS version, that would need a targeted investigation rather than a blanket recreation.

**Change:**
`systemDidWake` now only restarts the poller (which already calls `cpuMonitor.reset()` and
`networkMonitor.reset()` internally). No `StatusBarController` recreation. No display
change notification handler needed — ControlCenter repositions status items automatically
when display topology changes.

---

## [1.0.9] - 2026-04-03

- Fix: reset monitor state on wake to prevent post-sleep crash (NetworkMonitor UInt64 overflow)

## [1.0.8] - 2026-03-28

- Fix: cache arrow font as stored property to prevent nil crash during draw

## [1.0.7] and earlier

- See git log

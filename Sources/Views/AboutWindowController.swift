import AppKit

/// 现代原生极简高质感“关于”面板控制器（遵循 Apple 人机交互指南规范，内置版本自动更新与流式热安装）
final class AboutWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AboutWindowController()

    private var checkUpdateBtn: NSButton?
    private var buttonsContainer: NSView?
    private var downloadContainer: NSView?
    private var downloadStatusLabel: NSTextField?
    private var progressBar: NSProgressIndicator?
    private var cancelBtn: NSButton?

    convenience init() {
        let windowWidth: CGFloat = 280
        let windowHeight: CGFloat = 272

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .documentWindow

        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        self.init(window: window)
        window.delegate = self
        setupContentView()
    }

    private func setupContentView() {
        guard let window = window else { return }

        // 1. 底层现代毛玻璃环境材质
        let visualEffect = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        window.contentView = visualEffect

        let container = NSView(frame: visualEffect.bounds)
        container.autoresizingMask = [.width, .height]
        visualEffect.addSubview(container)

        let contentW: CGFloat = 280
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.8.3"

        // 2. 软件主图标（柔和环境光物理阴影 + 连续平滑圆角）
        let iconSize: CGFloat = 64
        let iconX = (contentW - iconSize) / 2
        let iconY: CGFloat = 174

        let shadowView = NSView(frame: NSRect(x: iconX, y: iconY, width: iconSize, height: iconSize))
        shadowView.wantsLayer = true
        shadowView.layer?.shadowColor = NSColor.black.cgColor
        shadowView.layer?.shadowOpacity = 0.16
        shadowView.layer?.shadowRadius = 10
        shadowView.layer?.shadowOffset = CGSize(width: 0, height: -3)

        let iconImageView = NSImageView(frame: shadowView.bounds)
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        if let appIcon = NSApplication.shared.applicationIconImage {
            iconImageView.image = appIcon
        } else if let fallback = NSImage(systemSymbolName: "waveform.path.ecg.rectangle", accessibilityDescription: "Qstats") {
            let config = NSImage.SymbolConfiguration(pointSize: 44, weight: .medium)
            iconImageView.image = fallback.withSymbolConfiguration(config)
        }
        iconImageView.wantsLayer = true
        iconImageView.layer?.cornerRadius = 14
        iconImageView.layer?.masksToBounds = true
        shadowView.addSubview(iconImageView)
        container.addSubview(shadowView)

        // 3. 应用标题
        let titleLabel = NSTextField(labelWithString: "Qstats")
        titleLabel.frame = NSRect(x: 20, y: 144, width: contentW - 40, height: 22)
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .labelColor
        container.addSubview(titleLabel)

        // 4. 版本号展示
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.frame = NSRect(x: 20, y: 126, width: contentW - 40, height: 16)
        versionLabel.alignment = .center
        versionLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor
        container.addSubview(versionLabel)

        // 5. 核心定位介绍
        let descLabel = NSTextField(labelWithString: "原生轻量 · 状态栏监控与截图套件")
        descLabel.frame = NSRect(x: 16, y: 100, width: contentW - 32, height: 18)
        descLabel.alignment = .center
        descLabel.font = .systemFont(ofSize: 11, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        container.addSubview(descLabel)

        // 6. 极细微分割线
        let line = NSBox(frame: NSRect(x: 24, y: 88, width: contentW - 48, height: 1))
        line.boxType = .separator
        container.addSubview(line)

        // 7. 操作按钮容器
        let btnAreaH: CGFloat = 46
        let btnAreaY: CGFloat = 34
        let buttonsBox = NSView(frame: NSRect(x: 0, y: btnAreaY, width: contentW, height: btnAreaH))
        container.addSubview(buttonsBox)
        self.buttonsContainer = buttonsBox

        let btnW: CGFloat = 100
        let btnH: CGFloat = 24
        let spacing: CGFloat = 12
        let totalBtnW = btnW * 2 + spacing
        let startX = (contentW - totalBtnW) / 2
        let btnY: CGFloat = 11

        let updateBtn = NSButton(title: "检查更新", target: self, action: #selector(checkForUpdates))
        updateBtn.frame = NSRect(x: startX, y: btnY, width: btnW, height: btnH)
        updateBtn.bezelStyle = .inline
        updateBtn.isBordered = false
        updateBtn.wantsLayer = true
        updateBtn.layer?.cornerRadius = 12
        updateBtn.font = .systemFont(ofSize: 11, weight: .semibold)
        updateBtn.layer?.borderWidth = 0.8
        updateBtn.layer?.borderColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 67 / 255.0, green: 233 / 255.0, blue: 201 / 255.0, alpha: 0.4)
                : NSColor(red: 13 / 255.0, green: 148 / 255.0, blue: 136 / 255.0, alpha: 0.3)
        }.cgColor
        updateBtn.layer?.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 67 / 255.0, green: 233 / 255.0, blue: 201 / 255.0, alpha: 0.15)
                : NSColor(red: 13 / 255.0, green: 148 / 255.0, blue: 136 / 255.0, alpha: 0.1)
        }.cgColor
        updateBtn.contentTintColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 67 / 255.0, green: 233 / 255.0, blue: 201 / 255.0, alpha: 1.0)
                : NSColor(red: 13 / 255.0, green: 148 / 255.0, blue: 136 / 255.0, alpha: 1.0)
        }
        buttonsBox.addSubview(updateBtn)
        self.checkUpdateBtn = updateBtn

        let githubBtn = NSButton(title: "GitHub 仓库", target: self, action: #selector(openGitHub))
        githubBtn.frame = NSRect(x: startX + btnW + spacing, y: btnY, width: btnW, height: btnH)
        githubBtn.bezelStyle = .inline
        githubBtn.isBordered = false
        githubBtn.wantsLayer = true
        githubBtn.layer?.cornerRadius = 12
        githubBtn.font = .systemFont(ofSize: 11, weight: .medium)
        githubBtn.layer?.borderWidth = 0.8
        githubBtn.layer?.borderColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.18)
                : NSColor.black.withAlphaComponent(0.12)
        }.cgColor
        githubBtn.layer?.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.black.withAlphaComponent(0.04)
        }.cgColor
        githubBtn.contentTintColor = .labelColor
        buttonsBox.addSubview(githubBtn)

        // 8. 下载进度容器（初始隐藏，热更激活时平滑渐显）
        let dlBox = NSView(frame: NSRect(x: 20, y: btnAreaY - 2, width: contentW - 40, height: btnAreaH + 4))
        dlBox.isHidden = true
        container.addSubview(dlBox)
        self.downloadContainer = dlBox

        let dlStatus = NSTextField(labelWithString: "正在连接下载服务器…")
        dlStatus.frame = NSRect(x: 0, y: 30, width: contentW - 40, height: 16)
        dlStatus.alignment = .center
        dlStatus.font = .systemFont(ofSize: 10.5, weight: .medium)
        dlStatus.textColor = .secondaryLabelColor
        dlBox.addSubview(dlStatus)
        self.downloadStatusLabel = dlStatus

        let progress = NSProgressIndicator(frame: NSRect(x: 4, y: 16, width: contentW - 48, height: 6))
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0.0
        progress.maxValue = 100.0
        progress.doubleValue = 0.0
        progress.controlSize = .small
        dlBox.addSubview(progress)
        self.progressBar = progress

        let cancel = NSButton(title: "取消更新", target: self, action: #selector(cancelUpdate))
        cancel.frame = NSRect(x: (contentW - 40 - 70) / 2, y: -2, width: 70, height: 16)
        cancel.bezelStyle = .inline
        cancel.isBordered = false
        cancel.font = .systemFont(ofSize: 10, weight: .regular)
        cancel.contentTintColor = .tertiaryLabelColor
        dlBox.addSubview(cancel)
        self.cancelBtn = cancel

        // 9. 底部精简版权信息
        let copyrightLabel = NSTextField(labelWithString: "© 2026 Qstats. 保留所有权利。")
        copyrightLabel.frame = NSRect(x: 20, y: 12, width: contentW - 40, height: 14)
        copyrightLabel.alignment = .center
        copyrightLabel.font = .systemFont(ofSize: 9.5, weight: .regular)
        copyrightLabel.textColor = .tertiaryLabelColor
        container.addSubview(copyrightLabel)
    }

    func show() {
        guard let window = window else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/qg-hs/Qstats") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 检查更新核心流程（集成自动下载热更与架构适配）

    @objc func checkForUpdates() {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.8.3"

        checkUpdateBtn?.isEnabled = false
        checkUpdateBtn?.title = "检查中…"

        func resetBtn() {
            DispatchQueue.main.async { [weak self] in
                self?.checkUpdateBtn?.isEnabled = true
                self?.checkUpdateBtn?.title = "检查更新"
            }
        }

        AppUpdateManager.shared.checkForUpdates { [weak self] result in
            DispatchQueue.main.async {
                resetBtn()
                guard let self = self else { return }

                switch result {
                case .failure(let error):
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = "检查更新失败"
                    alert.informativeText = "无法连接至 GitHub Releases 检查服务：\n\(error.localizedDescription)"
                    alert.addButton(withTitle: "前往 GitHub Releases 网页")
                    alert.addButton(withTitle: "好")
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let url = URL(string: "https://github.com/qg-hs/Qstats/releases/latest") {
                            NSWorkspace.shared.open(url)
                        }
                    }

                case .success(let releaseOpt):
                    guard let release = releaseOpt else { return }
                    NSApplication.shared.activate(ignoringOtherApps: true)

                    let hasNewVersion = AppUpdateManager.isVersion(release.version, newerThan: currentVersion)
                    if hasNewVersion {
                        let alert = NSAlert()
                        alert.alertStyle = .informational
                        alert.messageText = "发现新版本 Qstats v\(release.version)"
                        let desc = release.releaseNotes.isEmpty
                            ? "包含最新功能更新、UI 改进与性能优化。"
                            : release.releaseNotes
                        alert.informativeText = "检测到可用新版本：v\(release.version)（当前运行：v\(currentVersion)）。\n\n更新内容：\n\(desc.prefix(320))"

                        let canAutoUpdate = release.matchedAsset != nil
                        if canAutoUpdate {
                            alert.addButton(withTitle: "立即自动更新并重启")
                            alert.addButton(withTitle: "前往 GitHub 下载")
                            alert.addButton(withTitle: "稍后")
                        } else {
                            alert.addButton(withTitle: "前往 GitHub 下载")
                            alert.addButton(withTitle: "稍后")
                        }

                        let response = alert.runModal()
                        if canAutoUpdate && response == .alertFirstButtonReturn {
                            // 启动应用内流式下载与自更新
                            if let asset = release.matchedAsset {
                                self.startAutoUpdate(asset: asset, version: release.version)
                            }
                        } else if (!canAutoUpdate && response == .alertFirstButtonReturn) || (canAutoUpdate && response == .alertSecondButtonReturn) {
                            NSWorkspace.shared.open(release.releasePageURL)
                        }
                    } else {
                        let alert = NSAlert()
                        alert.alertStyle = .informational
                        alert.messageText = "已是最新版本"
                        alert.informativeText = "当前运行的 Qstats v\(currentVersion) 已经是最新版本，所有监控与截图组件均处于最新状态。"
                        alert.addButton(withTitle: "好")
                        alert.addButton(withTitle: "查看版本历史")
                        if alert.runModal() == .alertSecondButtonReturn {
                            NSWorkspace.shared.open(release.releasePageURL)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 应用内自动下载与热替换执行

    private func startAutoUpdate(asset: ReleaseAsset, version: String) {
        buttonsContainer?.isHidden = true
        downloadContainer?.isHidden = false
        cancelBtn?.isHidden = false
        progressBar?.isIndeterminate = false
        progressBar?.doubleValue = 0.0
        downloadStatusLabel?.stringValue = "正在连接下载服务器…"

        AppUpdateManager.shared.startDownload(
            asset: asset,
            onProgress: { [weak self] progressState in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch progressState {
                    case .downloading(let progress, _, _, let speedBytesPerSec):
                        self.progressBar?.isIndeterminate = false
                        self.progressBar?.doubleValue = progress * 100.0
                        let speedStr = self.formatSpeed(speedBytesPerSec)
                        let percent = Int(progress * 100.0)
                        if speedStr.isEmpty {
                            self.downloadStatusLabel?.stringValue = "正在下载 v\(version) (\(percent)%)…"
                        } else {
                            self.downloadStatusLabel?.stringValue = "正在下载 v\(version) (\(percent)% · \(speedStr))"
                        }

                    case .extractingAndInstalling:
                        self.progressBar?.isIndeterminate = true
                        self.progressBar?.startAnimation(nil)
                        self.cancelBtn?.isHidden = true
                        self.downloadStatusLabel?.stringValue = "正在校验解包并重启应用…"
                    }
                }
            },
            onCompletion: { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    switch result {
                    case .success:
                        // 进程即将被守护脚本重启并终止
                        break
                    case .failure(let error):
                        self.restoreButtonsState()
                        if case UpdateError.cancelled = error {
                            return
                        }
                        let alert = NSAlert()
                        alert.alertStyle = .warning
                        alert.messageText = "自动更新失败"
                        alert.informativeText = "\(error.localizedDescription)\n\n您可以前往 GitHub Releases 页面手动下载安装。"
                        alert.addButton(withTitle: "前往 GitHub Releases")
                        alert.addButton(withTitle: "好")
                        if alert.runModal() == .alertFirstButtonReturn {
                            if let url = URL(string: "https://github.com/qg-hs/Qstats/releases/latest") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
            }
        )
    }

    @objc private func cancelUpdate() {
        AppUpdateManager.shared.cancelDownload()
        restoreButtonsState()
    }

    private func restoreButtonsState() {
        downloadContainer?.isHidden = true
        buttonsContainer?.isHidden = false
        progressBar?.stopAnimation(nil)
        progressBar?.doubleValue = 0.0
        checkUpdateBtn?.isEnabled = true
        checkUpdateBtn?.title = "检查更新"
    }

    private func formatSpeed(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 0 else { return "" }
        if bytesPerSec < (1024.0 * 1024.0 - 512.0) {
            let kb = bytesPerSec / 1024.0
            return "\(Int(round(kb))) KB/s"
        }
        let mb = bytesPerSec / (1024.0 * 1024.0)
        let roundedMB = (mb * 10.0).rounded() / 10.0
        return String(format: "%.1f MB/s", roundedMB)
    }

    @objc private func closeAbout() {
        window?.close()
    }

    func windowDidResignKey(_ notification: Notification) {
    }
}

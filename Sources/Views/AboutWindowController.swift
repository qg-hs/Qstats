import AppKit

/// 现代原生极简高质感“关于”面板控制器（遵循 Apple 人机交互指南规范，内置版本更新检测）
final class AboutWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AboutWindowController()

    private var checkUpdateBtn: NSButton?

    convenience init() {
        let windowWidth: CGFloat = 280
        let windowHeight: CGFloat = 264

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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.7.0"

        // 2. 软件主图标（柔和环境光物理阴影 + 连续平滑圆角）
        let iconSize: CGFloat = 64
        let iconX = (contentW - iconSize) / 2
        let iconY: CGFloat = 166

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
        titleLabel.frame = NSRect(x: 20, y: 136, width: contentW - 40, height: 22)
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .labelColor
        container.addSubview(titleLabel)

        // 4. 版本号展示
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.frame = NSRect(x: 20, y: 118, width: contentW - 40, height: 16)
        versionLabel.alignment = .center
        versionLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor
        container.addSubview(versionLabel)

        // 5. 核心定位介绍
        let descLabel = NSTextField(labelWithString: "原生轻量 · 状态栏监控与截图套件")
        descLabel.frame = NSRect(x: 16, y: 92, width: contentW - 32, height: 18)
        descLabel.alignment = .center
        descLabel.font = .systemFont(ofSize: 11, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        container.addSubview(descLabel)

        // 6. 极细微分割线
        let line = NSBox(frame: NSRect(x: 24, y: 80, width: contentW - 48, height: 1))
        line.boxType = .separator
        container.addSubview(line)

        // 7. 关键改动：将“检查更新”整合至“关于”面板，并排居中排布操作按钮
        let btnW: CGFloat = 100
        let btnH: CGFloat = 24
        let spacing: CGFloat = 12
        let totalBtnW = btnW * 2 + spacing
        let startX = (contentW - totalBtnW) / 2
        let btnY: CGFloat = 42

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
        container.addSubview(updateBtn)
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
        container.addSubview(githubBtn)

        // 8. 底部精简版权信息
        let copyrightLabel = NSTextField(labelWithString: "© 2026 Qstats. 保留所有权利。")
        copyrightLabel.frame = NSRect(x: 20, y: 14, width: contentW - 40, height: 14)
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

    // MARK: - 关键改动：将版本更新检测内置于“关于”控制器中（带 API 频控降级 Fallback 容灾）
    @objc func checkForUpdates() {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.7.0"
        let repoAPI = "https://api.github.com/repos/qg-hs/Qstats/releases/latest"
        let fallbackURL = "https://raw.githubusercontent.com/qg-hs/Qstats/main/VERSION"
        let releasesURL = URL(string: "https://github.com/qg-hs/Qstats/releases/latest")!

        guard let apiURL = URL(string: repoAPI) else { return }

        checkUpdateBtn?.isEnabled = false
        checkUpdateBtn?.title = "检查中…"

        func resetBtn() {
            DispatchQueue.main.async { [weak self] in
                self?.checkUpdateBtn?.isEnabled = true
                self?.checkUpdateBtn?.title = "检查更新"
            }
        }

        func presentVersionAlert(remoteVersion: String, body: String?) {
            DispatchQueue.main.async {
                resetBtn()
                NSApplication.shared.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.alertStyle = .informational

                let hasNewVersion = remoteVersion.compare(currentVersion, options: .numeric) == .orderedDescending
                if hasNewVersion {
                    alert.messageText = "发现新版本 Qstats v\(remoteVersion)"
                    let desc = body ?? "包含最新功能更新、UI 改进与性能优化。"
                    alert.informativeText = "检测到可用更新：v\(remoteVersion)（当前运行：v\(currentVersion)）。\n\n更新内容：\n\(desc.prefix(320))"
                    alert.addButton(withTitle: "立即下载新版本")
                    alert.addButton(withTitle: "稍后")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSWorkspace.shared.open(releasesURL)
                    }
                } else {
                    alert.messageText = "已是最新版本"
                    alert.informativeText = "当前运行的 Qstats v\(currentVersion) 已经是最新版本，所有系统监控与截图组件均处于最新状态。"
                    alert.addButton(withTitle: "好")
                    alert.addButton(withTitle: "查看版本历史")
                    if alert.runModal() == .alertSecondButtonReturn {
                        NSWorkspace.shared.open(releasesURL)
                    }
                }
            }
        }

        func fallbackCheck() {
            guard let rawURL = URL(string: fallbackURL) else { resetBtn(); return }
            var rawReq = URLRequest(url: rawURL)
            rawReq.timeoutInterval = 5
            rawReq.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            URLSession.shared.dataTask(with: rawReq) { data, _, _ in
                if let data, let rawStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawStr.isEmpty {
                    let cleaned = rawStr.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                    presentVersionAlert(remoteVersion: cleaned, body: nil)
                } else {
                    DispatchQueue.main.async {
                        resetBtn()
                        NSApplication.shared.activate(ignoringOtherApps: true)
                        let alert = NSAlert()
                        alert.alertStyle = .informational
                        alert.messageText = "版本更新检查"
                        alert.informativeText = "当前安装版本：Qstats v\(currentVersion)\n未能连接到 GitHub Releases 检查服务。您可以直接前往 GitHub 仓库主页查看最新动态。"
                        alert.addButton(withTitle: "前往 GitHub Releases")
                        alert.addButton(withTitle: "取消")
                        if alert.runModal() == .alertFirstButtonReturn {
                            NSWorkspace.shared.open(releasesURL)
                        }
                    }
                }
            }.resume()
        }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 8
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Qstats-macOS", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                fallbackCheck()
                return
            }

            let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let body = json["body"] as? String
            presentVersionAlert(remoteVersion: remoteVersion, body: body)
        }.resume()
    }

    @objc private func closeAbout() {
        window?.close()
    }

    func windowDidResignKey(_ notification: Notification) {
    }
}

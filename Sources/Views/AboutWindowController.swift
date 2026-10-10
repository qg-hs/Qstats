import AppKit

/// 现代原生极简高质感“关于”面板控制器（遵循 Apple 人机交互指南规范，剔除冗余修饰，保证深浅色下呼吸感与高阶质感）
final class AboutWindowController: NSWindowController, NSWindowDelegate {
    static let shared = AboutWindowController()

    convenience init() {
        let windowWidth: CGFloat = 280
        let windowHeight: CGFloat = 250

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

        // 关键改动：隐藏无用的最小化与缩放交通灯，消除左上角视觉残缺
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
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.6.0"

        // 2. 软件主图标（柔和环境光物理阴影 + 连续平滑圆角，移除生硬白色描边框）
        let iconSize: CGFloat = 64
        let iconX = (contentW - iconSize) / 2
        let iconY: CGFloat = 152

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

        // 3. 应用标题（简洁有力的原生 Typography）
        let titleLabel = NSTextField(labelWithString: "Qstats")
        titleLabel.frame = NSRect(x: 20, y: 122, width: contentW - 40, height: 22)
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        titleLabel.textColor = .labelColor
        container.addSubview(titleLabel)

        // 4. 版本号规范展示（抛弃突兀的彩色大药丸，回归原生副标排版）
        let versionLabel = NSTextField(labelWithString: "Version \(version) (Build 130)")
        versionLabel.frame = NSRect(x: 20, y: 104, width: contentW - 40, height: 16)
        versionLabel.alignment = .center
        versionLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor
        container.addSubview(versionLabel)

        // 5. 核心定位介绍
        let descLabel = NSTextField(labelWithString: "原生轻量 · 状态栏监控与截图套件")
        descLabel.frame = NSRect(x: 16, y: 76, width: contentW - 32, height: 18)
        descLabel.alignment = .center
        descLabel.font = .systemFont(ofSize: 11, weight: .regular)
        descLabel.textColor = .secondaryLabelColor
        container.addSubview(descLabel)

        // 6. 极细微分割线
        let line = NSBox(frame: NSRect(x: 24, y: 64, width: contentW - 48, height: 1))
        line.boxType = .separator
        container.addSubview(line)

        // 7. 优雅的 GitHub 链接胶囊按钮
        let btnW: CGFloat = 94
        let btnH: CGFloat = 22
        let githubBtn = NSButton(title: "GitHub 仓库", target: self, action: #selector(openGitHub))
        githubBtn.frame = NSRect(x: (contentW - btnW) / 2, y: 32, width: btnW, height: btnH)
        githubBtn.bezelStyle = .inline
        githubBtn.isBordered = false
        githubBtn.wantsLayer = true
        githubBtn.layer?.cornerRadius = 11
        githubBtn.font = .systemFont(ofSize: 10.5, weight: .medium)
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

    @objc private func closeAbout() {
        window?.close()
    }

    // 支持 ESC 快捷键直接关闭面板
    func windowDidResignKey(_ notification: Notification) {
        // 保留窗口打开状态，供用户专注查看
    }
}

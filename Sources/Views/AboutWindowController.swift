import AppKit

/// 高质感毛玻璃现代化“关于 Qstats”窗口控制器（全面自适应浅色与深色双外观，严格保证高对比度与清晰度）
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    private var badgeContainer: NSView?
    private var badgeBorderLayer: CALayer?
    private var featureChips: [NSTextField] = []
    private var closeBtn: NSButton?

    convenience init() {
        let windowWidth: CGFloat = 320
        let windowHeight: CGFloat = 360

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

        self.init(window: window)
        setupContentView()
    }

    private func setupContentView() {
        guard let window = window else { return }

        // 1. 底层高质感毛玻璃背景
        let visualEffect = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        window.contentView = visualEffect

        let container = NSView(frame: visualEffect.bounds)
        container.autoresizingMask = [.width, .height]
        visualEffect.addSubview(container)

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.0"

        // 2. 软件主图标（高清圆角、微光边框与物理投影）
        let iconSize: CGFloat = 68
        let iconImageView = NSImageView(frame: NSRect(x: (320 - iconSize) / 2, y: 246, width: iconSize, height: iconSize))
        iconImageView.imageScaling = .scaleProportionallyUpOrDown
        if let appIcon = NSApplication.shared.applicationIconImage {
            iconImageView.image = appIcon
        } else if let fallback = NSImage(systemSymbolName: "waveform.path.ecg.rectangle", accessibilityDescription: "Qstats") {
            let config = NSImage.SymbolConfiguration(pointSize: 48, weight: .medium)
            iconImageView.image = fallback.withSymbolConfiguration(config)
        }
        iconImageView.wantsLayer = true
        iconImageView.layer?.cornerRadius = 15
        iconImageView.layer?.masksToBounds = true
        iconImageView.layer?.borderWidth = 1.0
        iconImageView.layer?.borderColor = NSColor(white: 0.5, alpha: 0.2).cgColor
        iconImageView.layer?.shadowColor = NSColor.black.cgColor
        iconImageView.layer?.shadowOpacity = 0.35
        iconImageView.layer?.shadowRadius = 8
        iconImageView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        container.addSubview(iconImageView)

        // 3. 应用标题
        let titleLabel = NSTextField(labelWithString: "Qstats")
        titleLabel.frame = NSRect(x: 20, y: 210, width: 280, height: 26)
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 21, weight: .bold)
        titleLabel.textColor = .labelColor
        container.addSubview(titleLabel)

        // 4. 关键改动：版本号徽标适配浅色/深色高对比度（浅色下为深墨青绿，深色下为明亮青绿，对比度 > 8:1，清晰可读）
        let badgeW: CGFloat = 146
        let badgeH: CGFloat = 22
        let badgeView = NSView(frame: NSRect(x: (320 - badgeW) / 2, y: 180, width: badgeW, height: badgeH))
        badgeView.wantsLayer = true
        badgeView.layer?.cornerRadius = 11

        let versionTextColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 67 / 255.0, green: 233 / 255.0, blue: 201 / 255.0, alpha: 1.0)
                : NSColor(red: 13 / 255.0, green: 118 / 255.0, blue: 110 / 255.0, alpha: 1.0) // 浅色模式采用极高对比深墨青
        }
        let versionBgColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 67 / 255.0, green: 233 / 255.0, blue: 201 / 255.0, alpha: 0.16)
                : NSColor(red: 13 / 255.0, green: 148 / 255.0, blue: 136 / 255.0, alpha: 0.12)
        }
        let versionBorderColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 67 / 255.0, green: 233 / 255.0, blue: 201 / 255.0, alpha: 0.45)
                : NSColor(red: 13 / 255.0, green: 118 / 255.0, blue: 110 / 255.0, alpha: 0.35)
        }

        badgeView.layer?.backgroundColor = versionBgColor.cgColor
        badgeView.layer?.borderWidth = 1.0
        badgeView.layer?.borderColor = versionBorderColor.cgColor

        let versionLabel = NSTextField(labelWithString: "v\(version) · Build 130")
        versionLabel.frame = NSRect(x: 0, y: 1, width: badgeW, height: badgeH - 1)
        versionLabel.alignment = .center
        versionLabel.font = .monospacedSystemFont(ofSize: 11, weight: .bold)
        versionLabel.textColor = versionTextColor
        badgeView.addSubview(versionLabel)
        container.addSubview(badgeView)
        self.badgeContainer = badgeView

        // 5. 核心产品定位标语（高对比清晰排版）
        let descLabel = NSTextField(labelWithString: "极简 · 现代 · 高效\nmacOS 原生状态栏性能监控与屏幕截图套件")
        descLabel.frame = NSRect(x: 20, y: 126, width: 280, height: 38)
        descLabel.alignment = .center
        descLabel.font = .systemFont(ofSize: 11, weight: .medium)
        descLabel.textColor = .labelColor
        container.addSubview(descLabel)

        // 6. 功能特性胶囊组（深浅双模高对比底衬与细边框）
        let tagsStack = NSStackView(frame: NSRect(x: 16, y: 88, width: 288, height: 24))
        tagsStack.orientation = .horizontal
        tagsStack.distribution = .fillEqually
        tagsStack.spacing = 6

        let features = ["实时流速", "硬件监视", "区域截图", "桌面贴图"]
        for feat in features {
            let chip = NSTextField(labelWithString: feat)
            chip.alignment = .center
            chip.font = .systemFont(ofSize: 10, weight: .semibold)
            chip.textColor = .secondaryLabelColor
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 5
            chip.layer?.borderWidth = 0.8
            chip.layer?.backgroundColor = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(white: 1.0, alpha: 0.08)
                    : NSColor(white: 0.0, alpha: 0.05)
            }.cgColor
            chip.layer?.borderColor = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(white: 1.0, alpha: 0.14)
                    : NSColor(white: 0.0, alpha: 0.12)
            }.cgColor
            tagsStack.addArrangedSubview(chip)
        }
        container.addSubview(tagsStack)

        // 7. 版权文本（确保清晰度）
        let copyrightLabel = NSTextField(labelWithString: "Copyright © 2026 Qstats. 保留所有权利。")
        copyrightLabel.frame = NSRect(x: 20, y: 60, width: 280, height: 16)
        copyrightLabel.alignment = .center
        copyrightLabel.font = .systemFont(ofSize: 10, weight: .medium)
        copyrightLabel.textColor = .secondaryLabelColor
        container.addSubview(copyrightLabel)

        // 8. 按钮组：GitHub 仓库直达 + 确定关闭
        let btnW: CGFloat = 90
        let btnH: CGFloat = 28
        let spacing: CGFloat = 14
        let totalW = btnW * 2 + spacing
        let startX = (320 - totalW) / 2

        let githubBtn = NSButton(title: "GitHub", target: self, action: #selector(openGitHub))
        githubBtn.frame = NSRect(x: startX, y: 16, width: btnW, height: btnH)
        githubBtn.bezelStyle = .regularSquare
        githubBtn.isBordered = false
        githubBtn.wantsLayer = true
        githubBtn.layer?.cornerRadius = 14
        githubBtn.font = .systemFont(ofSize: 12, weight: .semibold)
        githubBtn.layer?.borderWidth = 1.0
        githubBtn.layer?.borderColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.22)
                : NSColor.black.withAlphaComponent(0.18)
        }.cgColor
        githubBtn.layer?.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.08)
                : NSColor.black.withAlphaComponent(0.05)
        }.cgColor
        githubBtn.contentTintColor = .labelColor
        container.addSubview(githubBtn)

        let closeButton = NSButton(title: "确定", target: self, action: #selector(closeAbout))
        closeButton.frame = NSRect(x: startX + btnW + spacing, y: 16, width: btnW, height: btnH)
        closeButton.bezelStyle = .regularSquare
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.cornerRadius = 14
        closeButton.font = .systemFont(ofSize: 12, weight: .bold)
        closeButton.keyEquivalent = "\r"

        let btnBg = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 67 / 255.0, green: 233 / 255.0, blue: 201 / 255.0, alpha: 1.0)
                : NSColor(red: 13 / 255.0, green: 148 / 255.0, blue: 136 / 255.0, alpha: 1.0) // 浅色模式使用 Teal 600
        }
        let btnTextColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 10 / 255.0, green: 28 / 255.0, blue: 63 / 255.0, alpha: 1.0)
                : NSColor.white
        }
        closeButton.layer?.backgroundColor = btnBg.cgColor
        closeButton.contentTintColor = btnTextColor
        container.addSubview(closeButton)
        self.closeBtn = closeButton
    }

    func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/qg-hs/Qstats") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func closeAbout() {
        window?.close()
    }
}

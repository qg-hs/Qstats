import AppKit
import ServiceManagement
import CoreGraphics

/// 高质感毛玻璃现代化“设置”偏好窗口控制器（含自启与屏幕录制权限的 NSSwitch 滑块控制及状态动态监听）
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private var autoStartSwitch: NSSwitch!
    private var autoStartStatusLabel: NSTextField!

    private var screenRecordSwitch: NSSwitch!
    private var screenRecordStatusBadge: NSTextField!

    private var activeObserver: NSObjectProtocol?

    convenience init() {
        let windowWidth: CGFloat = 380
        let windowHeight: CGFloat = 290

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
        registerObservers()
    }

    deinit {
        if let observer = activeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupContentView() {
        guard let window = window else { return }

        // 1. 底层高质感毛玻璃材质
        let visualEffect = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        window.contentView = visualEffect

        let container = NSView(frame: visualEffect.bounds)
        container.autoresizingMask = [.width, .height]
        visualEffect.addSubview(container)

        let contentW: CGFloat = 380

        // 2. 顶部标题栏图标与文案
        let headerIcon = NSImageView(frame: NSRect(x: 24, y: 236, width: 28, height: 28))
        if let icon = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "设置") {
            let iconConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            headerIcon.image = icon.withSymbolConfiguration(iconConfig)
            headerIcon.contentTintColor = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 67 / 255.0, green: 233 / 255.0, blue: 201 / 255.0, alpha: 1.0)
                    : NSColor(red: 13 / 255.0, green: 148 / 255.0, blue: 136 / 255.0, alpha: 1.0)
            }
        }
        container.addSubview(headerIcon)

        let titleLabel = NSTextField(labelWithString: "偏好设置")
        titleLabel.frame = NSRect(x: 60, y: 242, width: 200, height: 22)
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .labelColor
        container.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "管理系统自启行为与核心功能授权")
        subtitleLabel.frame = NSRect(x: 60, y: 226, width: 280, height: 16)
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        container.addSubview(subtitleLabel)

        // 3. 卡片 1：开机自启动设置卡片
        let card1 = createCardView(frame: NSRect(x: 20, y: 136, width: contentW - 40, height: 72))
        container.addSubview(card1)

        let autoStartIcon = NSImageView(frame: NSRect(x: 14, y: 24, width: 24, height: 24))
        if let icon = NSImage(systemSymbolName: "bolt.horizontal.circle.fill", accessibilityDescription: "开机自启") {
            let conf = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            autoStartIcon.image = icon.withSymbolConfiguration(conf)
            autoStartIcon.contentTintColor = .systemTeal
        }
        card1.addSubview(autoStartIcon)

        let autoStartTitle = NSTextField(labelWithString: "开机自启动")
        autoStartTitle.frame = NSRect(x: 48, y: 40, width: 180, height: 18)
        autoStartTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        autoStartTitle.textColor = .labelColor
        card1.addSubview(autoStartTitle)

        let autoStartDesc = NSTextField(labelWithString: "登录 macOS 系统后自动在后台运行 Qstats")
        autoStartDesc.frame = NSRect(x: 48, y: 22, width: 210, height: 16)
        autoStartDesc.font = .systemFont(ofSize: 10.5, weight: .regular)
        autoStartDesc.textColor = .secondaryLabelColor
        card1.addSubview(autoStartDesc)

        autoStartStatusLabel = NSTextField(labelWithString: "未启用")
        autoStartStatusLabel.frame = NSRect(x: 48, y: 7, width: 210, height: 14)
        autoStartStatusLabel.font = .systemFont(ofSize: 9.5, weight: .medium)
        autoStartStatusLabel.textColor = .tertiaryLabelColor
        card1.addSubview(autoStartStatusLabel)

        autoStartSwitch = NSSwitch(frame: NSRect(x: contentW - 40 - 54, y: 24, width: 44, height: 24))
        autoStartSwitch.target = self
        autoStartSwitch.action = #selector(autoStartSwitchChanged(_:))
        card1.addSubview(autoStartSwitch)

        // 4. 卡片 2：屏幕录制权限卡片
        let card2 = createCardView(frame: NSRect(x: 20, y: 52, width: contentW - 40, height: 72))
        container.addSubview(card2)

        let screenIcon = NSImageView(frame: NSRect(x: 14, y: 24, width: 24, height: 24))
        if let icon = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "屏幕录制") {
            let conf = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
            screenIcon.image = icon.withSymbolConfiguration(conf)
            screenIcon.contentTintColor = .systemOrange
        }
        card2.addSubview(screenIcon)

        let screenTitle = NSTextField(labelWithString: "屏幕录制权限")
        screenTitle.frame = NSRect(x: 48, y: 40, width: 120, height: 18)
        screenTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        screenTitle.textColor = .labelColor
        card2.addSubview(screenTitle)

        screenRecordStatusBadge = NSTextField(labelWithString: "检查中")
        screenRecordStatusBadge.frame = NSRect(x: 168, y: 41, width: 90, height: 16)
        screenRecordStatusBadge.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        card2.addSubview(screenRecordStatusBadge)

        let screenDesc = NSTextField(labelWithString: "用于区域截图、取色与全屏画布（系统隐私要求）")
        screenDesc.frame = NSRect(x: 48, y: 15, width: 220, height: 24)
        screenDesc.font = .systemFont(ofSize: 10.5, weight: .regular)
        screenDesc.textColor = .secondaryLabelColor
        card2.addSubview(screenDesc)

        screenRecordSwitch = NSSwitch(frame: NSRect(x: contentW - 40 - 54, y: 24, width: 44, height: 24))
        screenRecordSwitch.target = self
        screenRecordSwitch.action = #selector(screenRecordSwitchChanged(_:))
        card2.addSubview(screenRecordSwitch)

        // 5. 底部操作栏按钮组
        let sysPrefBtn = NSButton(title: "系统设置…", target: self, action: #selector(openSystemSettings))
        sysPrefBtn.frame = NSRect(x: 20, y: 14, width: 88, height: 26)
        sysPrefBtn.bezelStyle = .regularSquare
        sysPrefBtn.isBordered = false
        sysPrefBtn.wantsLayer = true
        sysPrefBtn.layer?.cornerRadius = 13
        sysPrefBtn.font = .systemFont(ofSize: 11, weight: .medium)
        sysPrefBtn.layer?.borderWidth = 1.0
        sysPrefBtn.layer?.borderColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.2)
                : NSColor.black.withAlphaComponent(0.15)
        }.cgColor
        sysPrefBtn.layer?.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.black.withAlphaComponent(0.04)
        }.cgColor
        container.addSubview(sysPrefBtn)

        let relaunchBtn = NSButton(title: "重启应用", target: self, action: #selector(relaunchApp))
        relaunchBtn.frame = NSRect(x: 114, y: 14, width: 78, height: 26)
        relaunchBtn.bezelStyle = .regularSquare
        relaunchBtn.isBordered = false
        relaunchBtn.wantsLayer = true
        relaunchBtn.layer?.cornerRadius = 13
        relaunchBtn.font = .systemFont(ofSize: 11, weight: .medium)
        relaunchBtn.layer?.borderWidth = 1.0
        relaunchBtn.layer?.borderColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.2)
                : NSColor.black.withAlphaComponent(0.15)
        }.cgColor
        relaunchBtn.layer?.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.black.withAlphaComponent(0.04)
        }.cgColor
        container.addSubview(relaunchBtn)

        let doneBtn = NSButton(title: "完成", target: self, action: #selector(closeSettings))
        doneBtn.frame = NSRect(x: contentW - 20 - 74, y: 14, width: 74, height: 26)
        doneBtn.bezelStyle = .regularSquare
        doneBtn.isBordered = false
        doneBtn.wantsLayer = true
        doneBtn.layer?.cornerRadius = 13
        doneBtn.font = .systemFont(ofSize: 11.5, weight: .bold)
        doneBtn.keyEquivalent = "\r"

        let btnBg = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 67 / 255.0, green: 233 / 255.0, blue: 201 / 255.0, alpha: 1.0)
                : NSColor(red: 13 / 255.0, green: 148 / 255.0, blue: 136 / 255.0, alpha: 1.0)
        }
        doneBtn.layer?.backgroundColor = btnBg.cgColor
        doneBtn.contentTintColor = .black
        container.addSubview(doneBtn)
    }

    private func createCardView(frame: NSRect) -> NSView {
        let card = NSView(frame: frame)
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1.0
        card.layer?.borderColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.08)
        }.cgColor
        card.layer?.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(white: 1.0, alpha: 0.05)
                : NSColor(white: 0.0, alpha: 0.03)
        }.cgColor
        return card
    }

    private func registerObservers() {
        // 当用户切换应用（例如从 macOS 系统设置授权后切回 Qstats）时，自动刷新权限开关与状态
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    func show() {
        guard let window = window else { return }
        refreshStatus()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// 刷新所有开关与状态展示
    func refreshStatus() {
        // 1. 开机自启动状态
        let isAutoStart = LaunchAtLoginManager.shared.isEnabled
        autoStartSwitch.state = isAutoStart ? .on : .off
        autoStartStatusLabel.stringValue = "系统状态：\(LaunchAtLoginManager.shared.statusDescription)"

        // 2. 屏幕录制权限状态
        let hasScreenCapture = CGPreflightScreenCaptureAccess()
        screenRecordSwitch.state = hasScreenCapture ? .on : .off
        if hasScreenCapture {
            screenRecordStatusBadge.stringValue = "● 已授权"
            screenRecordStatusBadge.textColor = .systemGreen
        } else {
            screenRecordStatusBadge.stringValue = "● 未授权"
            screenRecordStatusBadge.textColor = .systemOrange
        }
    }

    // MARK: - 控件事件交互

    @objc private func autoStartSwitchChanged(_ sender: NSSwitch) {
        let targetState = (sender.state == .on)
        do {
            try LaunchAtLoginManager.shared.setEnabled(targetState)
            refreshStatus()
        } catch {
            // 异常回滚 Switch 状态并提示用户
            sender.state = targetState ? .off : .on
            refreshStatus()

            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "无法切换开机自启动"
            alert.informativeText = "系统调用失败：\(error.localizedDescription)\n\n提示：若在开发调试模式运行，请确保 Qstats 已打包并在 /Applications 目录下执行。"
            alert.addButton(withTitle: "好")
            alert.runModal()
        }
    }

    @objc private func screenRecordSwitchChanged(_ sender: NSSwitch) {
        let wantsEnable = (sender.state == .on)
        let currentlyGranted = CGPreflightScreenCaptureAccess()

        if wantsEnable {
            if currentlyGranted {
                refreshStatus()
                return
            }
            // 触发系统权限弹窗并打开系统设置
            CGRequestScreenCaptureAccess()
            ScreenCaptureService.openSystemSettings()

            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .informational
            alert.messageText = "已发起屏幕录制权限申请"
            alert.informativeText = "系统限制：在【系统设置 -> 隐私与安全性 -> 屏幕录制】中开启 Qstats 开关后，需【重启应用】才能使授权生效。"
            alert.addButton(withTitle: "重启应用")
            alert.addButton(withTitle: "稍后手动重启")
            if alert.runModal() == .alertFirstButtonReturn {
                ScreenCaptureService.relaunchApp()
            }
        } else {
            // macOS 隐私限制：第三方程序无法直接代码撤销 TCC 权限
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "需要通过系统设置关闭权限"
            alert.informativeText = "macOS 系统安全策略保护：应用程序无法直接撤销已授予的屏幕录制权限。如需关闭，请前往【系统设置】手动移除。"
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "取消")
            if alert.runModal() == .alertFirstButtonReturn {
                ScreenCaptureService.openSystemSettings()
            }
        }
        // 保持 switch 与实际权限同步
        refreshStatus()
    }

    @objc private func openSystemSettings() {
        ScreenCaptureService.openSystemSettings()
    }

    @objc private func relaunchApp() {
        ScreenCaptureService.relaunchApp()
    }

    @objc private func closeSettings() {
        window?.close()
    }
}

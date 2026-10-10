import AppKit
import ServiceManagement
import CoreGraphics
import Carbon.HIToolbox

/// 高质感毛玻璃现代化“设置”偏好窗口控制器
/// 纳管：快捷键配置、菜单栏指标显示、图表样式、开机自启与系统屏幕录制权限
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    // 外部联动回调
    var onConfigChanged: ((AppConfig) -> Void)?
    var onShortcutChanged: (() -> Void)?

    private enum ShortcutType {
        case screenshot
        case pinClipboard
    }

    // 快捷键展示胶囊
    private var screenshotBadge: NSTextField!
    private var screenshotResetBtn: NSButton!
    private var pinBadge: NSTextField!
    private var pinResetBtn: NSButton!

    // 菜单栏显示指标复选框
    private var metricCheckboxes: [Metric: NSButton] = [:]

    // 样式选择弹窗按钮
    private var stylePopups: [Metric: NSPopUpButton] = [:]

    // 系统自启与权限控件
    private var autoStartSwitch: NSSwitch!
    private var autoStartStatusLabel: NSTextField!
    private var screenRecordSwitch: NSSwitch!
    private var screenRecordStatusBadge: NSTextField!

    private var activeObserver: NSObjectProtocol?
    private var currentConfig = AppConfig()

    private let styleOptions: [(key: String, title: String)] = [
        ("circle", "精简圆环"),
        ("bar", "圆角进度条"),
        ("vbar", "竖向进度条"),
        ("text", "百分比数字")
    ]

    convenience init() {
        let windowWidth: CGFloat = 430
        let windowHeight: CGFloat = 590

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

        // 底层毛玻璃材质
        let visualEffect = NSVisualEffectView(frame: window.contentView?.bounds ?? .zero)
        visualEffect.material = .hudWindow
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        window.contentView = visualEffect

        let rootContainer = NSView(frame: visualEffect.bounds)
        rootContainer.autoresizingMask = [.width, .height]
        visualEffect.addSubview(rootContainer)

        let contentW: CGFloat = 430
        let contentH: CGFloat = 590

        // 1. 顶部 Header 标题栏
        let headerIcon = NSImageView(frame: NSRect(x: 24, y: contentH - 46, width: 28, height: 28))
        if let icon = NSImage(systemSymbolName: "gearshape.fill", accessibilityDescription: "设置") {
            let iconConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
            headerIcon.image = icon.withSymbolConfiguration(iconConfig)
            headerIcon.contentTintColor = NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 67 / 255.0, green: 233 / 255.0, blue: 201 / 255.0, alpha: 1.0)
                    : NSColor(red: 13 / 255.0, green: 148 / 255.0, blue: 136 / 255.0, alpha: 1.0)
            }
        }
        rootContainer.addSubview(headerIcon)

        let titleLabel = NSTextField(labelWithString: "偏好设置")
        titleLabel.frame = NSRect(x: 60, y: contentH - 40, width: 200, height: 22)
        titleLabel.font = .systemFont(ofSize: 16, weight: .bold)
        titleLabel.textColor = .labelColor
        rootContainer.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "快捷键、指标监控、图表样式与系统授权")
        subtitleLabel.frame = NSRect(x: 60, y: contentH - 56, width: 320, height: 16)
        subtitleLabel.font = .systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = .secondaryLabelColor
        rootContainer.addSubview(subtitleLabel)

        // 2. 滚动区域包裹所有卡片
        let bottomBarHeight: CGFloat = 48
        let topHeaderHeight: CGFloat = 64
        let scrollY = bottomBarHeight
        let scrollH = contentH - bottomBarHeight - topHeaderHeight

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: scrollY, width: contentW, height: scrollH))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let totalCardsHeight: CGFloat = 530
        let clipView = NSClipView(frame: NSRect(x: 0, y: 0, width: contentW, height: scrollH))
        clipView.drawsBackground = false
        scrollView.contentView = clipView

        let cardsContainer = NSFlippedView(frame: NSRect(x: 0, y: 0, width: contentW, height: totalCardsHeight))
        scrollView.documentView = cardsContainer
        rootContainer.addSubview(scrollView)

        // MARK: - 卡片 1：全局快捷键设置板块（区域截图 + 剪贴板贴图）
        let card1 = createCardView(frame: NSRect(x: 20, y: 8, width: contentW - 40, height: 114))
        cardsContainer.addSubview(card1)

        let shortcutHeader = createSectionHeader(icon: "keyboard.fill", title: "全局快捷键设置")
        shortcutHeader.frame = NSRect(x: 14, y: 12, width: 200, height: 18)
        card1.addSubview(shortcutHeader)

        // 行 1：区域截图
        let (row1Badge, row1Reset) = buildShortcutRow(
            in: card1, y: 38,
            iconName: "viewfinder",
            title: "区域截图",
            type: .screenshot
        )
        screenshotBadge = row1Badge
        screenshotResetBtn = row1Reset

        // 行 2：剪贴板贴图
        let (row2Badge, row2Reset) = buildShortcutRow(
            in: card1, y: 74,
            iconName: "pin.fill",
            title: "剪贴板贴图",
            type: .pinClipboard
        )
        pinBadge = row2Badge
        pinResetBtn = row2Reset

        // MARK: - 卡片 2：菜单栏指标显示板块
        let card2 = createCardView(frame: NSRect(x: 20, y: 130, width: contentW - 40, height: 104))
        cardsContainer.addSubview(card2)

        let metricHeader = createSectionHeader(icon: "menubar.rectangle", title: "菜单栏指标显示")
        metricHeader.frame = NSRect(x: 14, y: 12, width: 200, height: 18)
        card2.addSubview(metricHeader)

        let showAllBtn = NSButton(title: "显示全部", target: self, action: #selector(showAllMetricsClicked))
        showAllBtn.bezelStyle = .inline
        showAllBtn.font = .systemFont(ofSize: 10.5, weight: .medium)
        showAllBtn.frame = NSRect(x: contentW - 40 - 78, y: 10, width: 66, height: 20)
        card2.addSubview(showAllBtn)

        let cbGrid = [Metric.cpu, Metric.memory, Metric.gpu, Metric.network]
        let colWidth: CGFloat = 88
        for (i, metric) in cbGrid.enumerated() {
            let x = 16 + CGFloat(i) * colWidth
            let cb = NSButton(checkboxWithTitle: metric.title, target: self, action: #selector(metricCheckboxToggled(_:)))
            cb.font = .systemFont(ofSize: 12, weight: .regular)
            cb.frame = NSRect(x: x, y: 44, width: colWidth, height: 22)
            card2.addSubview(cb)
            metricCheckboxes[metric] = cb
        }

        let metricHint = NSTextField(labelWithString: "至少保留一项监控指标在菜单栏中展示 · 实时生效")
        metricHint.frame = NSRect(x: 16, y: 74, width: 340, height: 16)
        metricHint.font = .systemFont(ofSize: 10, weight: .regular)
        metricHint.textColor = .tertiaryLabelColor
        card2.addSubview(metricHint)

        // MARK: - 卡片 3：显示样式板块
        let card3 = createCardView(frame: NSRect(x: 20, y: 242, width: contentW - 40, height: 136))
        cardsContainer.addSubview(card3)

        let styleHeader = createSectionHeader(icon: "slider.horizontal.3", title: "监控显示样式")
        styleHeader.frame = NSRect(x: 14, y: 12, width: 200, height: 18)
        card3.addSubview(styleHeader)

        let styleMetrics = [Metric.cpu, Metric.memory, Metric.gpu]
        for (idx, metric) in styleMetrics.enumerated() {
            let y = 38 + CGFloat(idx) * 30
            let label = NSTextField(labelWithString: "\(metric.title) 样式")
            label.frame = NSRect(x: 16, y: y + 2, width: 80, height: 20)
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.textColor = .labelColor
            card3.addSubview(label)

            let popup = NSPopUpButton(frame: NSRect(x: 100, y: y, width: 140, height: 24), pullsDown: false)
            popup.bezelStyle = .rounded
            popup.font = .systemFont(ofSize: 11, weight: .regular)
            for opt in styleOptions {
                popup.addItem(withTitle: opt.title)
            }
            popup.target = self
            popup.action = #selector(stylePopupChanged(_:))
            card3.addSubview(popup)
            stylePopups[metric] = popup
        }

        // MARK: - 卡片 4：系统自启与屏幕录制权限
        let card4 = createCardView(frame: NSRect(x: 20, y: 386, width: contentW - 40, height: 136))
        cardsContainer.addSubview(card4)

        let permHeader = createSectionHeader(icon: "shield.lefthalf.filled", title: "系统偏好与核心授权")
        permHeader.frame = NSRect(x: 14, y: 12, width: 220, height: 18)
        card4.addSubview(permHeader)

        // 自启行
        let autoStartLabel = NSTextField(labelWithString: "开机自启动")
        autoStartLabel.frame = NSRect(x: 16, y: 40, width: 100, height: 18)
        autoStartLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        card4.addSubview(autoStartLabel)

        autoStartStatusLabel = NSTextField(labelWithString: "未启用")
        autoStartStatusLabel.frame = NSRect(x: 16, y: 60, width: 260, height: 14)
        autoStartStatusLabel.font = .systemFont(ofSize: 10, weight: .regular)
        autoStartStatusLabel.textColor = .secondaryLabelColor
        card4.addSubview(autoStartStatusLabel)

        autoStartSwitch = NSSwitch(frame: NSRect(x: contentW - 40 - 54, y: 42, width: 44, height: 24))
        autoStartSwitch.target = self
        autoStartSwitch.action = #selector(autoStartSwitchChanged(_:))
        card4.addSubview(autoStartSwitch)

        // 录制权限行
        let screenLabel = NSTextField(labelWithString: "屏幕录制权限")
        screenLabel.frame = NSRect(x: 16, y: 86, width: 100, height: 18)
        screenLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        card4.addSubview(screenLabel)

        screenRecordStatusBadge = NSTextField(labelWithString: "检查中")
        screenRecordStatusBadge.frame = NSRect(x: 118, y: 87, width: 80, height: 16)
        screenRecordStatusBadge.font = .monospacedSystemFont(ofSize: 10, weight: .bold)
        card4.addSubview(screenRecordStatusBadge)

        let screenDesc = NSTextField(labelWithString: "用于区域截图、取色与全屏画布（系统隐私保护）")
        screenDesc.frame = NSRect(x: 16, y: 106, width: 280, height: 14)
        screenDesc.font = .systemFont(ofSize: 10, weight: .regular)
        screenDesc.textColor = .secondaryLabelColor
        card4.addSubview(screenDesc)

        screenRecordSwitch = NSSwitch(frame: NSRect(x: contentW - 40 - 54, y: 88, width: 44, height: 24))
        screenRecordSwitch.target = self
        screenRecordSwitch.action = #selector(screenRecordSwitchChanged(_:))
        card4.addSubview(screenRecordSwitch)

        // 3. 底部固定操作栏
        let sysPrefBtn = NSButton(title: "系统设置…", target: self, action: #selector(openSystemSettings))
        sysPrefBtn.frame = NSRect(x: 20, y: 12, width: 88, height: 26)
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
        rootContainer.addSubview(sysPrefBtn)

        let relaunchBtn = NSButton(title: "重启应用", target: self, action: #selector(relaunchApp))
        relaunchBtn.frame = NSRect(x: 114, y: 12, width: 78, height: 26)
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
        rootContainer.addSubview(relaunchBtn)

        let doneBtn = NSButton(title: "完成", target: self, action: #selector(closeSettings))
        doneBtn.frame = NSRect(x: contentW - 20 - 74, y: 12, width: 74, height: 26)
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
        rootContainer.addSubview(doneBtn)
    }

    // 辅助方法：构建快捷键行
    private func buildShortcutRow(
        in card: NSView,
        y: CGFloat,
        iconName: String,
        title: String,
        type: ShortcutType
    ) -> (NSTextField, NSButton) {
        let iconView = NSImageView(frame: NSRect(x: 16, y: y + 2, width: 16, height: 16))
        if let img = NSImage(systemSymbolName: iconName, accessibilityDescription: title) {
            let conf = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
            iconView.image = img.withSymbolConfiguration(conf)
            iconView.contentTintColor = .secondaryLabelColor
        }
        card.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.frame = NSRect(x: 38, y: y + 1, width: 100, height: 18)
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .medium)
        titleLabel.textColor = .labelColor
        card.addSubview(titleLabel)

        let badge = NSTextField(labelWithString: "—")
        badge.frame = NSRect(x: 146, y: y, width: 76, height: 20)
        badge.font = .monospacedSystemFont(ofSize: 12, weight: .bold)
        badge.alignment = .center
        badge.textColor = .systemTeal
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        badge.layer?.borderWidth = 1
        badge.layer?.borderColor = NSColor.systemTeal.withAlphaComponent(0.35).cgColor
        badge.layer?.backgroundColor = NSColor.systemTeal.withAlphaComponent(0.08).cgColor
        card.addSubview(badge)

        let editBtn = NSButton(title: "设置…", target: self, action: type == .screenshot ? #selector(customizeScreenshotClicked) : #selector(customizePinClicked))
        editBtn.bezelStyle = .rounded
        editBtn.font = .systemFont(ofSize: 11, weight: .medium)
        editBtn.frame = NSRect(x: 230, y: y - 2, width: 68, height: 24)
        card.addSubview(editBtn)

        let resetBtn = NSButton(title: "恢复默认", target: self, action: type == .screenshot ? #selector(resetScreenshotClicked) : #selector(resetPinClicked))
        resetBtn.bezelStyle = .rounded
        resetBtn.font = .systemFont(ofSize: 11, weight: .regular)
        resetBtn.frame = NSRect(x: 302, y: y - 2, width: 76, height: 24)
        card.addSubview(resetBtn)

        return (badge, resetBtn)
    }

    private func createSectionHeader(icon: String, title: String) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 18))
        let imgView = NSImageView(frame: NSRect(x: 0, y: 1, width: 16, height: 16))
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            let conf = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            imgView.image = img.withSymbolConfiguration(conf)
            imgView.contentTintColor = .systemTeal
        }
        view.addSubview(imgView)

        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 20, y: 0, width: 190, height: 18)
        label.font = .systemFont(ofSize: 12, weight: .bold)
        label.textColor = .labelColor
        view.addSubview(label)
        return view
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
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    func show(with config: AppConfig? = nil) {
        if let config { self.currentConfig = config }
        else { self.currentConfig = AppConfig.load() }

        guard let window = window else { return }
        refreshStatus()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// 刷新所有开关、指标勾选、样式及快捷键状态
    func refreshStatus() {
        // 1. 刷新快捷键展示
        let shotShortcut = ShortcutPreferences.loadScreenshot()
        screenshotBadge.stringValue = shotShortcut.displayName
        screenshotResetBtn.isEnabled = (shotShortcut != .defaultScreenshot)

        let pinShortcut = ShortcutPreferences.loadPinClipboard()
        pinBadge.stringValue = pinShortcut.displayName
        pinResetBtn.isEnabled = (pinShortcut != .defaultPinClipboard)

        // 2. 刷新菜单栏指标勾选
        for (metric, cb) in metricCheckboxes {
            cb.state = currentConfig.isVisible(metric) ? .on : .off
        }

        // 3. 刷新监控显示样式
        for (metric, popup) in stylePopups {
            let curStyle = currentConfig.style(for: metric)
            if let idx = styleOptions.firstIndex(where: { $0.key == curStyle }) {
                popup.selectItem(at: idx)
            }
        }

        // 4. 开机自启动状态
        let isAutoStart = LaunchAtLoginManager.shared.isEnabled
        autoStartSwitch.state = isAutoStart ? .on : .off
        autoStartStatusLabel.stringValue = "系统状态：\(LaunchAtLoginManager.shared.statusDescription)"

        // 5. 屏幕录制权限状态
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

    // MARK: - 快捷键交互

    @objc private func customizeScreenshotClicked() {
        customizeShortcut(for: .screenshot)
    }

    @objc private func customizePinClicked() {
        customizeShortcut(for: .pinClipboard)
    }

    @objc private func resetScreenshotClicked() {
        applyShortcut(.defaultScreenshot, for: .screenshot)
    }

    @objc private func resetPinClicked() {
        applyShortcut(.defaultPinClipboard, for: .pinClipboard)
    }

    private func customizeShortcut(for type: ShortcutType) {
        let current = type == .screenshot ? ShortcutPreferences.loadScreenshot() : ShortcutPreferences.loadPinClipboard()
        let title = type == .screenshot ? "设置区域截图快捷键" : "设置剪贴板贴图快捷键"

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "按下新的组合键，需包含修饰键（⌃、⌥、⇧ 或 ⌘）。"
        let recorder = ShortcutRecorderView(shortcut: current)
        alert.accessoryView = recorder
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "取消")

        NSApplication.shared.activate(ignoringOtherApps: true)
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === alert.window else { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if modifiers.isEmpty && [UInt16(53), UInt16(36), UInt16(48)].contains(event.keyCode) {
                return event
            }
            guard let shortcut = KeyboardShortcut(event: event) else {
                recorder.rejectInput()
                return nil
            }
            recorder.shortcut = shortcut
            return nil
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }

        guard alert.runModal() == .alertFirstButtonReturn, let newShortcut = recorder.shortcut else { return }
        applyShortcut(newShortcut, for: type)
    }

    private func applyShortcut(_ shortcut: KeyboardShortcut, for type: ShortcutType) {
        switch type {
        case .screenshot:
            let prev = ShortcutPreferences.loadScreenshot()
            if GlobalHotKeyManager.shared.registerScreenshotShortcut(shortcut) {
                ShortcutPreferences.saveScreenshot(shortcut)
            } else {
                _ = GlobalHotKeyManager.shared.registerScreenshotShortcut(prev)
                showShortcutUnavailable(shortcut)
            }
        case .pinClipboard:
            let prev = ShortcutPreferences.loadPinClipboard()
            if GlobalHotKeyManager.shared.registerPinClipboardShortcut(shortcut) {
                ShortcutPreferences.savePinClipboard(shortcut)
            } else {
                _ = GlobalHotKeyManager.shared.registerPinClipboardShortcut(prev)
                showShortcutUnavailable(shortcut)
            }
        }
        refreshStatus()
        onShortcutChanged?()
    }

    private func showShortcutUnavailable(_ shortcut: KeyboardShortcut) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "快捷键 \(shortcut.displayName) 不可用"
        alert.informativeText = "该组合键可能已被系统或其他应用占用，原快捷键保持不变。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - 菜单栏显示与样式联动

    @objc private func metricCheckboxToggled(_ sender: NSButton) {
        // 根据发送者实例匹配对应的 Metric
        guard let (metric, _) = metricCheckboxes.first(where: { $0.value === sender }) else { return }
        var candidate = currentConfig

        if sender.state == .off && candidate.visibleMetricCount <= 1 {
            // 至少保留一项，阻止取消
            sender.state = .on
            NSSound.beep()
            return
        }

        if candidate.toggle(metric) {
            saveAndApply(candidate)
        }
    }

    @objc private func showAllMetricsClicked() {
        var candidate = currentConfig
        candidate.showCPU = true
        candidate.showMemory = true
        candidate.showGPU = true
        candidate.showNetwork = true
        saveAndApply(candidate)
    }

    @objc private func stylePopupChanged(_ sender: NSPopUpButton) {
        // 根据发送者实例匹配对应的 Metric
        guard let (metric, _) = stylePopups.first(where: { $0.value === sender }) else { return }
        let selectedIdx = sender.indexOfSelectedItem
        guard selectedIdx >= 0 && selectedIdx < styleOptions.count else { return }
        let newStyle = styleOptions[selectedIdx].key

        var candidate = currentConfig
        candidate.setStyle(newStyle, for: metric)
        saveAndApply(candidate)
    }

    private func saveAndApply(_ config: AppConfig) {
        do {
            try config.saveDisplayPreferences()
            currentConfig = config
            refreshStatus()
            onConfigChanged?(config)
        } catch {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "无法保存显示设置"
            alert.informativeText = "请检查配置文件的写入权限。\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    // MARK: - 自启与屏幕录制权限事件

    @objc private func autoStartSwitchChanged(_ sender: NSSwitch) {
        let targetState = (sender.state == .on)
        do {
            try LaunchAtLoginManager.shared.setEnabled(targetState)
            refreshStatus()
        } catch {
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

/// 顶部对齐翻转坐标系视图（保证卡片从上往下自顶向下顺序排列）
final class NSFlippedView: NSView {
    override var isFlipped: Bool { true }
}

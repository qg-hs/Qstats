import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusBarController: StatusBarController!
    private var poller: StatsPoller!
    private var menu: NSMenu!
    private var menuBuilder: StatsMenuBuilder!
    private var menuIsOpen = false
    private let screenshotCoordinator = ScreenshotCoordinator()
    private var shortcutAvailable = true
    private var screenshotShortcut = KeyboardShortcut.defaultScreenshot
    // 关键改动：新增剪贴板贴图全局快捷键状态
    private var pinClipboardShortcut = KeyboardShortcut.defaultPinClipboard
    private var config = AppConfig()

    /// overlay 已覆盖在菜单上方，等待 menuDidClose 后激活交互焦点
    private var pendingOverlayActivation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppConfig.createDefaultIfNeeded()
        config = AppConfig.load()
        statusBarController = StatusBarController(config: config)

        // 注册区域截图全局热键
        GlobalHotKeyManager.shared.onScreenshot = { [weak self] in self?.startScreenshot() }
        screenshotShortcut = ShortcutPreferences.loadScreenshot()
        shortcutAvailable = GlobalHotKeyManager.shared.registerScreenshotShortcut(screenshotShortcut)

        // 关键改动：注册剪贴板贴图全局热键
        GlobalHotKeyManager.shared.onPinClipboard = { [weak self] in self?.pinClipboardImage() }
        pinClipboardShortcut = ShortcutPreferences.loadPinClipboard()
        _ = GlobalHotKeyManager.shared.registerPinClipboardShortcut(pinClipboardShortcut)

        // 绑定偏好设置窗口的双向数据与菜单联动回调
        SettingsWindowController.shared.onConfigChanged = { [weak self] newConfig in
            self?.apply(newConfig)
        }
        SettingsWindowController.shared.onShortcutChanged = { [weak self] in
            guard let self else { return }
            self.screenshotShortcut = ShortcutPreferences.loadScreenshot()
            self.pinClipboardShortcut = ShortcutPreferences.loadPinClipboard()
            self.rebuildMenu()
        }

        rebuildMenu()
        poller = StatsPoller(config: config)
        poller.onUpdate = { [weak self] snapshot in
            guard let self else { return }
            self.statusBarController.display(snapshot)
            if self.menuIsOpen { self.menuBuilder.update(snapshot: snapshot) }
        }
        poller.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    private func rebuildMenu() {
        menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        // 关键改动：锁定菜单最小宽度为 220，配合网速定宽槽位彻底杜绝宽度变动抖动
        menu.minimumWidth = 220
        menuBuilder = StatsMenuBuilder(config: config)
        menuBuilder.buildMenu(menu)
        menuBuilder.update(snapshot: statusBarController.snapshot)

        // MARK: - 截图与贴图工具组（关键改动：右侧原生显示快捷键符号，与设置、退出一致）
        let screenshot = NSMenuItem(
            title: "区域截图",
            action: #selector(startScreenshot),
            keyEquivalent: screenshotShortcut.keyEquivalentChar
        )
        screenshot.keyEquivalentModifierMask = screenshotShortcut.keyEquivalentModifierMask
        screenshot.target = self
        screenshot.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "区域截图")
        menu.addItem(screenshot)

        let pinClipboard = NSMenuItem(
            title: "剪贴板贴图",
            action: #selector(pinClipboardImage),
            keyEquivalent: pinClipboardShortcut.keyEquivalentChar
        )
        pinClipboard.keyEquivalentModifierMask = pinClipboardShortcut.keyEquivalentModifierMask
        pinClipboard.target = self
        pinClipboard.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "贴图")
        menu.addItem(pinClipboard)
        menu.addItem(.separator())

        // MARK: - 设置与关于（关键改动：检查更新移入“关于”面板，“设置”去除省略号）
        let settingsItem = NSMenuItem(title: "设置", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "设置")
        menu.addItem(settingsItem)

        let aboutItem = NSMenuItem(title: "关于", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "关于")
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        // MARK: - 退出应用（文案规范收敛为“退出”）
        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusBarController.setMenu(menu)
    }

    private func apply(_ candidate: AppConfig) {
        do {
            try candidate.saveDisplayPreferences()
            config = candidate
            statusBarController.apply(config: config)
            DispatchQueue.main.async { [weak self] in self?.rebuildMenu() }
        } catch {
            NSApplication.shared.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "无法保存显示设置"
            alert.informativeText = "请检查配置文件的写入权限。\n\(error.localizedDescription)"
            alert.runModal()
        }
    }

    // MARK: - 截图核心调度（Seamless Overlay 架构）
    @objc private func startScreenshot() {
        if screenshotCoordinator.isCapturing {
            screenshotCoordinator.cancelCapture()
            return
        }

        if menuIsOpen {
            // 防抖：已有 overlay 正在等待激活，忽略重复按键
            guard !pendingOverlayActivation else { return }

            // 同步直接在当前主线程捕获屏幕像素（CGDisplayCreateImage 耗时 <8ms），
            // 确保 100% 捕获展开中的菜单，且完全避免子线程延迟导致的界面撕裂与闪烁
            guard let captures = screenshotCoordinator.captureScreensOnly() else { return }

            // ① 立即把 overlay window 盖在菜单上方（.screenSaver 层级高于菜单）
            //    底图已含菜单画面，用户视觉上菜单完全没有闪烁或消失
            screenshotCoordinator.showOverlay(captures)
            pendingOverlayActivation = true

            // ② 再关闭真实菜单（此时菜单已被 overlay 完全遮挡，退出模态追踪）
            menu.cancelTrackingWithoutAnimation()

            // ③ 注入空事件打破 nextEventMatchingMask 阻塞
            if let evt = NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0
            ) {
                NSApplication.shared.postEvent(evt, atStart: true)
            }

            // ④ 容错保障：0.15s 后若 menuDidClose 尚未回调，强制激活交互
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self, self.pendingOverlayActivation else { return }
                self.pendingOverlayActivation = false
                self.screenshotCoordinator.activateOverlay()
            }
        } else {
            screenshotCoordinator.startCapture()
        }
    }

    @objc private func pinClipboardImage() { screenshotCoordinator.pinClipboardImage() }

    // MARK: - 专属毛玻璃现代化"关于"独立面板
    @objc private func showAbout() {
        AboutWindowController.shared.show()
    }

    // MARK: - 偏好设置面板（整合快捷键、菜单栏指标显示、样式、自启与权限）
    @objc private func showSettings() {
        SettingsWindowController.shared.show(with: config)
    }

    func applicationWillTerminate(_ notification: Notification) {
        poller.stop()
        GlobalHotKeyManager.shared.unregister()
    }

    @objc private func systemDidWake() { poller.stop(); poller.start() }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        menuBuilder.update(snapshot: statusBarController.snapshot)
    }

    // MARK: - 菜单关闭后激活已覆盖的截图画布交互焦点
    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        if pendingOverlayActivation {
            pendingOverlayActivation = false
            // overlay 已在菜单上方显示，现在模态循环退出，激活键盘与鼠标焦点
            DispatchQueue.main.async { [weak self] in
                self?.screenshotCoordinator.activateOverlay()
            }
        }
    }

    @objc private func quit() { NSApplication.shared.terminate(nil) }
}

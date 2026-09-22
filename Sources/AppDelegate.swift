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
    private var config = AppConfig()

    /// overlay 已覆盖在菜单上方，等待 menuDidClose 后激活交互焦点
    private var pendingOverlayActivation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppConfig.createDefaultIfNeeded()
        config = AppConfig.load()
        statusBarController = StatusBarController(config: config)
        GlobalHotKeyManager.shared.onScreenshot = { [weak self] in self?.startScreenshot() }
        screenshotShortcut = ShortcutPreferences.load()
        shortcutAvailable = GlobalHotKeyManager.shared.registerScreenshotShortcut(screenshotShortcut)
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
        // 限制菜单最小宽度，防止过宽
        menu.minimumWidth = 200
        menuBuilder = StatsMenuBuilder(config: config)
        menuBuilder.buildMenu(menu)
        menuBuilder.update(snapshot: statusBarController.snapshot)

        // MARK: - 截图与贴图工具组
        let screenshot = NSMenuItem(title: "区域截图", action: #selector(startScreenshot), keyEquivalent: "")
        screenshot.target = self
        screenshot.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "区域截图")
        menu.addItem(screenshot)

        let shortcutMenu = NSMenu(title: "截图快捷键")
        shortcutMenu.autoenablesItems = false
        let shortcutStatus = NSMenuItem(
            title: shortcutAvailable ? "当前快捷键  \(screenshotShortcut.displayName)" : "\(screenshotShortcut.displayName) 已被占用",
            action: nil,
            keyEquivalent: ""
        )
        shortcutStatus.isEnabled = false
        shortcutMenu.addItem(shortcutStatus)
        shortcutMenu.addItem(.separator())
        let customizeShortcut = NSMenuItem(title: "自定义快捷键…", action: #selector(customizeScreenshotShortcut), keyEquivalent: "")
        customizeShortcut.target = self
        shortcutMenu.addItem(customizeShortcut)
        let resetShortcut = NSMenuItem(title: "恢复默认（⌥D）", action: #selector(resetScreenshotShortcut), keyEquivalent: "")
        resetShortcut.target = self
        resetShortcut.isEnabled = screenshotShortcut != .defaultScreenshot || !shortcutAvailable
        shortcutMenu.addItem(resetShortcut)
        let shortcutItem = NSMenuItem(title: "截图快捷键  \(screenshotShortcut.displayName)", action: nil, keyEquivalent: "")
        shortcutItem.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "截图快捷键")
        shortcutItem.submenu = shortcutMenu
        menu.addItem(shortcutItem)

        let pinClipboard = NSMenuItem(title: "剪贴板贴图", action: #selector(pinClipboardImage), keyEquivalent: "")
        pinClipboard.target = self
        pinClipboard.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "贴图")
        menu.addItem(pinClipboard)
        menu.addItem(.separator())

        // MARK: - 偏好与样式设置组
        let visibility = NSMenu(title: "菜单栏显示")
        visibility.autoenablesItems = false
        for metric in Metric.allCases {
            let item = NSMenuItem(title: metric.title, action: #selector(toggleMetric(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = metric.rawValue
            item.state = config.isVisible(metric) ? .on : .off
            item.isEnabled = !config.isVisible(metric) || config.visibleMetricCount > 1
            visibility.addItem(item)
        }
        visibility.addItem(.separator())
        let all = NSMenuItem(title: "显示全部", action: #selector(showAll), keyEquivalent: "")
        all.target = self
        visibility.addItem(all)
        let hint = NSMenuItem(title: "至少保留一项 · 自动保存", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        visibility.addItem(hint)
        let visibilityItem = NSMenuItem(title: "菜单栏显示", action: nil, keyEquivalent: "")
        visibilityItem.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "菜单栏显示")
        visibilityItem.submenu = visibility
        menu.addItem(visibilityItem)

        let appearance = NSMenu(title: "显示样式")
        for metric in [Metric.cpu, .memory, .gpu] {
            let choices = NSMenu(title: metric.title)
            for (style, title) in [("circle", "精简圆环"), ("bar", "圆角进度条"), ("vbar", "竖向进度条"), ("text", "百分比数字")] {
                let item = NSMenuItem(title: title, action: #selector(changeStyle(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = [metric.rawValue, style]
                item.state = config.style(for: metric) == style ? .on : .off
                choices.addItem(item)
            }
            let item = NSMenuItem(title: metric.title, action: nil, keyEquivalent: "")
            item.submenu = choices
            appearance.addItem(item)
        }
        let appearanceItem = NSMenuItem(title: "显示样式", action: nil, keyEquivalent: "")
        appearanceItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "显示样式")
        appearanceItem.submenu = appearance
        menu.addItem(appearanceItem)
        menu.addItem(.separator())

        // MARK: - 关键改动 2：添加"版本更新"与"关于"
        let checkUpdateItem = NSMenuItem(title: "检查更新…", action: #selector(checkForUpdates), keyEquivalent: "")
        checkUpdateItem.target = self
        checkUpdateItem.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "检查更新")
        menu.addItem(checkUpdateItem)

        let aboutItem = NSMenuItem(title: "关于 Qstats", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "关于")
        menu.addItem(aboutItem)
        menu.addItem(.separator())

        // MARK: - 退出应用
        let quitItem = NSMenuItem(title: "退出 Qstats", action: #selector(quit), keyEquivalent: "q")
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

    @objc private func toggleMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let metric = Metric(rawValue: raw) else { return }
        var candidate = config
        if candidate.toggle(metric) { apply(candidate) }
    }

    @objc private func showAll() {
        var candidate = config
        candidate.showCPU = true
        candidate.showMemory = true
        candidate.showGPU = true
        candidate.showNetwork = true
        apply(candidate)
    }

    @objc private func changeStyle(_ sender: NSMenuItem) {
        guard let values = sender.representedObject as? [String], values.count == 2,
              let metric = Metric(rawValue: values[0]) else { return }
        var candidate = config
        candidate.setStyle(values[1], for: metric)
        apply(candidate)
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

    @objc private func customizeScreenshotShortcut() {
        let alert = NSAlert()
        alert.messageText = "设置区域截图快捷键"
        alert.informativeText = "按下新的组合键，至少包含一个修饰键。"
        let recorder = ShortcutRecorderView(shortcut: screenshotShortcut)
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

        guard alert.runModal() == .alertFirstButtonReturn, let shortcut = recorder.shortcut else { return }
        applyScreenshotShortcut(shortcut)
    }

    @objc private func resetScreenshotShortcut() {
        applyScreenshotShortcut(.defaultScreenshot)
    }

    private func applyScreenshotShortcut(_ shortcut: KeyboardShortcut) {
        let previous = screenshotShortcut
        if GlobalHotKeyManager.shared.registerScreenshotShortcut(shortcut) {
            screenshotShortcut = shortcut
            shortcutAvailable = true
            ShortcutPreferences.save(shortcut)
        } else {
            shortcutAvailable = GlobalHotKeyManager.shared.registerScreenshotShortcut(previous)
            showShortcutUnavailable(shortcut)
        }
        DispatchQueue.main.async { [weak self] in self?.rebuildMenu() }
    }

    private func showShortcutUnavailable(_ shortcut: KeyboardShortcut) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "快捷键 \(shortcut.displayName) 不可用"
        alert.informativeText = "该组合键可能已被系统或其他应用占用。原快捷键保持不变。"
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    // MARK: - 关键改动 2：采用专属毛玻璃现代化"关于"独立面板
    @objc private func showAbout() {
        AboutWindowController.shared.show()
    }

    // MARK: - 对接 GitHub 最新仓库版本更新检测（带 API 频控降级 Fallback 容灾）
    @objc private func checkForUpdates() {
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.3.0"
        let repoAPI = "https://api.github.com/repos/qg-hs/Qstats/releases/latest"
        let fallbackURL = "https://raw.githubusercontent.com/qg-hs/Qstats/main/VERSION"
        let releasesURL = URL(string: "https://github.com/qg-hs/Qstats/releases/latest")!

        guard let apiURL = URL(string: repoAPI) else { return }

        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 8
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("Qstats-macOS", forHTTPHeaderField: "User-Agent")

        // 统一展示版本结果弹窗
        func presentVersionAlert(remoteVersion: String, body: String?) {
            DispatchQueue.main.async {
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

        // 降级 Fallback 通道：当 API 受限（如 HTTP 403 Rate Limit）时直接查询 raw 文本
        func fallbackCheck() {
            guard let rawURL = URL(string: fallbackURL) else { return }
            var rawReq = URLRequest(url: rawURL)
            rawReq.timeoutInterval = 5
            rawReq.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            URLSession.shared.dataTask(with: rawReq) { data, _, _ in
                if let data, let rawStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !rawStr.isEmpty {
                    let cleaned = rawStr.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
                    presentVersionAlert(remoteVersion: cleaned, body: nil)
                } else {
                    DispatchQueue.main.async {
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

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                // 主 API 异常（如 403 Rate Limit）时，无缝切换至 raw.githubusercontent.com 降级检测
                fallbackCheck()
                return
            }

            let remoteVersion = tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            let body = json["body"] as? String
            presentVersionAlert(remoteVersion: remoteVersion, body: body)
        }.resume()
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

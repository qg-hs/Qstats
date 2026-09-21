import AppKit

final class ScreenshotOverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ScreenshotCoordinator: NSObject, ScreenshotCanvasDelegate {
    private let captureService = ScreenCaptureService()
    private var overlayWindows: [ScreenshotOverlayWindow] = []
    private var pinnedImages: [PinnedImageController] = []

    var isCapturing: Bool { !overlayWindows.isEmpty }

    func startCapture() {
        if isCapturing { cancelCapture(); return }
        // 关键改动：先严格检验权限状态，若系统尚未授权则严禁挂载全屏黑色覆盖层
        guard captureService.hasPermission else {
            captureService.requestPermission()
            showPermissionAlert()
            return
        }
        do {
            let captures = try captureService.captureAllScreens()
            present(captures)
        } catch ScreenCaptureError.permissionDenied {
            captureService.requestPermission()
            showPermissionAlert()
        } catch {
            showError(title: "无法开始截图", message: error.localizedDescription)
        }
    }

    func pinClipboardImage() {
        guard let image = NSImage(pasteboard: .general) else {
            showError(title: "剪贴板中没有图片", message: "请先复制一张图片，再选择“贴图”。")
            return
        }
        createPinnedImage(image)
    }

    func cancelCapture() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
    }

    private func present(_ captures: [CapturedScreen]) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        overlayWindows = captures.map { capture in
            let window = ScreenshotOverlayWindow(contentRect: capture.screen.frame,
                                                  styleMask: [.borderless], backing: .buffered, defer: false,
                                                  screen: capture.screen)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isOpaque = true
            window.backgroundColor = .black
            window.hasShadow = false
            window.animationBehavior = .none
            window.acceptsMouseMovedEvents = true
            let canvas = ScreenshotCanvasView(capture: capture)
            canvas.delegate = self
            window.contentView = canvas
            window.setFrame(capture.screen.frame, display: true)
            window.orderFrontRegardless()
            return window
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        overlayWindows.first?.makeKeyAndOrderFront(nil)
        if let canvas = overlayWindows.first?.contentView {
            overlayWindows.first?.makeFirstResponder(canvas)
        }
    }

    func screenshotCanvasDidBeginSelection(_ canvas: ScreenshotCanvasView) {
        for window in overlayWindows where window.contentView !== canvas { window.orderOut(nil) }
        overlayWindows.removeAll { $0.contentView !== canvas }
        canvas.window?.makeKey()
        canvas.window?.makeFirstResponder(canvas)
    }

    func screenshotCanvasDidCancel(_ canvas: ScreenshotCanvasView) { cancelCapture() }

    func screenshotCanvas(_ canvas: ScreenshotCanvasView, didRequestPin image: NSImage) {
        let point = NSEvent.mouseLocation
        cancelCapture()
        createPinnedImage(image, near: point)
    }

    private func createPinnedImage(_ image: NSImage, near point: NSPoint? = nil) {
        let controller = PinnedImageController(image: image, near: point)
        pinnedImages.append(controller)
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.pinnedImages.removeAll { $0 === controller }
        }
    }

    private func showPermissionAlert() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "macOS 系统限制：在“系统设置”开启权限后，必须【重启应用】才能使新权限生效。若未重启，系统将持续返回黑屏或提示未授权。\n\n步骤：\n1. 点击【打开系统设置】，开启 Qstats 开关\n2. 开启后点击【重启应用】即可完成"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "重启应用")
        alert.addButton(withTitle: "稍后")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        } else if response == .alertSecondButtonReturn {
            relaunchApp()
        }
    }

    /// 重启应用以使 macOS TCC 权限生效
    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func showError(title: String, message: String) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}

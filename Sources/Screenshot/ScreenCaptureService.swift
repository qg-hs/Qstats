import AppKit
import CoreGraphics

struct CapturedScreen {
    let screen: NSScreen
    let image: NSImage
    let cgImage: CGImage
    let scale: CGFloat
}

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case unavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Qstats 没有屏幕录制权限"
        case .unavailable: return "无法读取当前显示器画面"
        }
    }
}

final class ScreenCaptureService {
    var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    func requestPermission() -> Bool { CGRequestScreenCaptureAccess() }

    func captureAllScreens() throws -> [CapturedScreen] {
        // 1. 严格权限前置校验：无权限时严禁进入截屏渲染，防止向屏幕投影空黑画面
        guard hasPermission else {
            throw ScreenCaptureError.permissionDenied
        }

        let captures = NSScreen.screens.compactMap(capture)
        guard !captures.isEmpty else {
            throw ScreenCaptureError.unavailable
        }

        return captures
    }

    private func capture(screen: NSScreen) -> CapturedScreen? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        guard let cgImage = CGDisplayCreateImage(displayID) else { return nil }
        guard cgImage.width > 0, cgImage.height > 0 else { return nil }
        let image = NSImage(cgImage: cgImage, size: screen.frame.size)
        let scale = CGFloat(cgImage.width) / max(1, screen.frame.width)
        return CapturedScreen(screen: screen, image: image, cgImage: cgImage, scale: scale)
    }

    /// 打开 macOS 屏幕录制隐私系统设置面板
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 重启应用以使 macOS TCC 权限变更生效
    static func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}


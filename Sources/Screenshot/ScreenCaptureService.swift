import AppKit
import CoreGraphics

struct CapturedScreen {
    let screen: NSScreen
    let image: NSImage
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

        // 2. 图像有效性安全防御：防止系统授权未重启过渡期返回全黑画面
        for cap in captures {
            if isImageEmptyOrBlack(cap.image) {
                throw ScreenCaptureError.permissionDenied
            }
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
        return CapturedScreen(screen: screen, image: image, scale: scale)
    }

    /// 快速抽样校验图像是否全黑
    private func isImageEmptyOrBlack(_ image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rep = NSBitmapImageRep(cgImage: cgImage) as NSBitmapImageRep? else { return true }
        let stepX = max(1, cgImage.width / 30)
        let stepY = max(1, cgImage.height / 30)
        for y in stride(from: 0, to: cgImage.height, by: stepY) {
            for x in stride(from: 0, to: cgImage.width, by: stepX) {
                if let color = rep.colorAt(x: x, y: y) {
                    if color.redComponent > 0.04 || color.greenComponent > 0.04 || color.blueComponent > 0.04 {
                        return false
                    }
                }
            }
        }
        return true
    }
}

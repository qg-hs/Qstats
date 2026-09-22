import AppKit
import CoreGraphics

/// 截图取色放大镜与像素检视卡片
final class ScreenshotMagnifierView: NSView {
    private let cgImage: CGImage
    private let captureScale: CGFloat
    private let screenHeight: CGFloat

    private var currentPoint: NSPoint = .zero
    private var pixelX: Int = 0
    private var pixelY: Int = 0
    private(set) var currentColorHex: String = "#000000"
    private var isCopiedToastActive: Bool = false
    private var toastTimer: Timer?

    private let cardWidth: CGFloat = 136
    private let previewHeight: CGFloat = 136
    private let cardHeight: CGFloat = 208
    private let sampleGridSize: Int = 17 // 17x17 物理像素采样窗口

    init(capture: CapturedScreen) {
        self.cgImage = capture.cgImage
        self.captureScale = capture.scale
        self.screenHeight = capture.screen.frame.height
        super.init(frame: NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight))

        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.borderWidth = 1.0
        layer?.borderColor = NSColor(white: 0.82, alpha: 0.8).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 8
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        toastTimer?.invalidate()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 事件完全穿透：放大镜仅做视觉检视，不截断任何画布鼠标事件
        nil
    }

    /// 根据当前光标位置采样并重布局放大镜卡片
    func update(cursorPoint: NSPoint, canvasBounds: NSRect) {
        self.currentPoint = cursorPoint

        // 1. 计算 Framebuffer 物理像素绝对坐标（Y 轴从顶部翻转）
        let px = Int(floor(cursorPoint.x * captureScale))
        let py = Int(floor((screenHeight - cursorPoint.y) * captureScale))
        self.pixelX = max(0, min(cgImage.width - 1, px))
        self.pixelY = max(0, min(cgImage.height - 1, py))

        // 2. 提取当前准星中心的单像素 HEX 色值
        extractPixelColor(x: pixelX, y: pixelY)

        // 3. 智能贴边翻转算法：防止卡片溢出屏幕可视区
        var originX = cursorPoint.x + 18
        var originY = cursorPoint.y - 18 - cardHeight

        // 右侧碰撞 -> 翻转至光标左侧
        if originX + cardWidth > canvasBounds.maxX - 10 {
            originX = cursorPoint.x - 18 - cardWidth
        }
        // 底部碰撞 -> 翻转至光标上方
        if originY < canvasBounds.minY + 10 {
            originY = cursorPoint.y + 18
        }
        // 左边界与顶边界防溢出保护
        if originX < canvasBounds.minX + 10 { originX = canvasBounds.minX + 10 }
        if originY + cardHeight > canvasBounds.maxY - 10 { originY = canvasBounds.maxY - cardHeight - 10 }

        self.frame = NSRect(x: originX, y: originY, width: cardWidth, height: cardHeight)
        needsDisplay = true
    }

    /// 复制当前提取到的 HEX 颜色到剪贴板
    @discardableResult
    func copyCurrentColor() -> Bool {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(currentColorHex, forType: .string)

        isCopiedToastActive = true
        needsDisplay = true

        toastTimer?.invalidate()
        toastTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
            self?.isCopiedToastActive = false
            self?.needsDisplay = true
        }
        return true
    }

    // MARK: - 绘制管线
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 整体卡片圆角路径裁剪
        let clipPath = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
        clipPath.addClip()

        let previewRect = CGRect(x: 0, y: bounds.height - previewHeight, width: cardWidth, height: previewHeight)
        let infoRect = CGRect(x: 0, y: 0, width: cardWidth, height: bounds.height - previewHeight)

        // ① 绘制上半部放大网格
        drawMagnifiedGrid(in: previewRect, context: ctx)

        // ② 绘制下半部信息面板底色与分割线
        ctx.saveGState()
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(infoRect)

        ctx.setStrokeColor(NSColor(white: 0.88, alpha: 1.0).cgColor)
        ctx.setLineWidth(1.0)
        ctx.move(to: CGPoint(x: 0, y: infoRect.maxY))
        ctx.addLine(to: CGPoint(x: cardWidth, y: infoRect.maxY))
        ctx.strokePath()
        ctx.restoreGState()

        // ③ 绘制文字信息
        drawInfoText(in: infoRect)
    }

    /// 最近邻高倍放大绘制光标周围的像素矩阵
    private func drawMagnifiedGrid(in rect: CGRect, context: CGContext) {
        let half = sampleGridSize / 2
        let cropRect = CGRect(x: pixelX - half, y: pixelY - half, width: sampleGridSize, height: sampleGridSize)

        // 边界保护采样
        if let cropped = cgImage.cropping(to: cropRect) {
            context.saveGState()
            // 关键改动行：强制设置为 .none 禁用平滑插值，呈现刀锋般锐利的单个像素色块
            context.interpolationQuality = .none
            context.draw(cropped, in: rect)
            context.restoreGState()
        } else {
            context.setFillColor(NSColor.black.cgColor)
            context.fill(rect)
        }

        // 绘制荧光绿十字准星（精准贯通中心像素）
        context.saveGState()
        let centerX = rect.midX
        let centerY = rect.midY
        let crossColor = NSColor(red: 0.0, green: 0.9, blue: 0.4, alpha: 0.95).cgColor

        context.setStrokeColor(crossColor)
        context.setLineWidth(1.5)

        // 水平线
        context.move(to: CGPoint(x: rect.minX, y: centerY))
        context.addLine(to: CGPoint(x: rect.maxX, y: centerY))

        // 垂直线
        context.move(to: CGPoint(x: centerX, y: rect.minY))
        context.addLine(to: CGPoint(x: centerX, y: rect.maxY))

        context.strokePath()
        context.restoreGState()
    }

    /// 绘制坐标、色值与快捷键提示
    private func drawInfoText(in rect: CGRect) {
        let labelFont = NSFont.systemFont(ofSize: 11, weight: .regular)
        let valueFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let hintFont = NSFont.systemFont(ofSize: 10, weight: .regular)

        let labelColor = NSColor(white: 0.15, alpha: 1.0)
        let hintColor = isCopiedToastActive
            ? NSColor(red: 0.0, green: 0.65, blue: 0.3, alpha: 1.0)
            : NSColor(white: 0.55, alpha: 1.0)

        let paddingH: CGFloat = 10
        let line1Y = rect.maxY - 22
        let line2Y = line1Y - 20
        let line3Y = rect.minY + 6

        // 坐标行
        let coordLabel = "坐标" as NSString
        let coordValue = "\(pixelX), \(pixelY)" as NSString
        coordLabel.draw(at: NSPoint(x: paddingH, y: line1Y), withAttributes: [
            .font: labelFont, .foregroundColor: labelColor
        ])
        let coordValSize = coordValue.size(withAttributes: [.font: valueFont])
        coordValue.draw(at: NSPoint(x: rect.width - paddingH - coordValSize.width, y: line1Y), withAttributes: [
            .font: valueFont, .foregroundColor: labelColor
        ])

        // 色值行
        let colorLabel = "色值" as NSString
        let colorValue = currentColorHex as NSString
        colorLabel.draw(at: NSPoint(x: paddingH, y: line2Y), withAttributes: [
            .font: labelFont, .foregroundColor: labelColor
        ])
        let colorValSize = colorValue.size(withAttributes: [.font: valueFont])
        colorValue.draw(at: NSPoint(x: rect.width - paddingH - colorValSize.width, y: line2Y), withAttributes: [
            .font: valueFont, .foregroundColor: labelColor
        ])

        // 提示行（按 ⌘+C 复制色值 / 已复制色值）
        let hintText = (isCopiedToastActive ? "✓ 已复制 \(currentColorHex)" : "按 ⌘+C 复制色值") as NSString
        hintText.draw(at: NSPoint(x: paddingH, y: line3Y), withAttributes: [
            .font: hintFont, .foregroundColor: hintColor
        ])
    }

    /// 从当前帧缓冲区中单像素解码 RGBA 32-bit 真实值并生成 HEX
    private func extractPixelColor(x: Int, y: Int) {
        let singleRect = CGRect(x: x, y: y, width: 1, height: 1)
        guard let singleCrop = cgImage.cropping(to: singleRect) else { return }

        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }

        ctx.draw(singleCrop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let r = pixel[0]
        let g = pixel[1]
        let b = pixel[2]
        self.currentColorHex = String(format: "#%02X%02X%02X", r, g, b)
    }
}

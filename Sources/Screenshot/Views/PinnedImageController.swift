import AppKit

final class PinnedImageController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    let image: NSImage
    private let imageView: PinnedImageView
    var onClose: (() -> Void)?

    init(image: NSImage, near point: NSPoint? = nil) {
        self.image = image
        let maxSize = NSSize(width: 720, height: 520)
        let initial = Self.fitted(image.size, inside: maxSize)
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let origin = point.map { NSPoint(x: $0.x - initial.width / 2, y: $0.y - initial.height / 2) }
            ?? NSPoint(x: screen.midX - initial.width / 2, y: screen.midY - initial.height / 2)
        panel = NSPanel(contentRect: NSRect(origin: origin, size: initial),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        imageView = PinnedImageView(image: image)
        super.init()
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = imageView
        panel.minSize = NSSize(width: 120, height: 80)
        imageView.controller = self
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 9
        imageView.layer?.masksToBounds = true
        imageView.layer?.borderWidth = 1
        imageView.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        panel.orderFrontRegardless()
    }

    func close() { panel.close() }

    func resize(by factor: CGFloat) {
        let current = panel.frame
        let aspectRatio = image.size.width / max(1.0, image.size.height)

        let proposedWidth = current.width * factor
        let clampedWidth = min(2560.0, max(120.0, proposedWidth))
        let clampedHeight = clampedWidth / aspectRatio

        let finalWidth: CGFloat
        let finalHeight: CGFloat
        if clampedHeight < 80.0 {
            finalHeight = 80.0
            finalWidth = finalHeight * aspectRatio
        } else if clampedHeight > 1800.0 {
            finalHeight = 1800.0
            finalWidth = finalHeight * aspectRatio
        } else {
            finalWidth = clampedWidth
            finalHeight = clampedHeight
        }

        let center = NSPoint(x: current.midX, y: current.midY)
        panel.setFrame(NSRect(x: center.x - finalWidth / 2, y: center.y - finalHeight / 2,
                              width: finalWidth, height: finalHeight), display: true, animate: false)
    }

    func adjustOpacity(by delta: CGFloat) {
        panel.alphaValue = min(1, max(0.2, panel.alphaValue + delta))
    }

    func windowWillClose(_ notification: Notification) { onClose?() }

    private static func fitted(_ size: NSSize, inside bounds: NSSize) -> NSSize {
        guard size.width > 0, size.height > 0 else { return NSSize(width: 420, height: 260) }
        let scale = min(1, min(bounds.width / size.width, bounds.height / size.height))
        return NSSize(width: max(120, size.width * scale), height: max(80, size.height * scale))
    }
}

enum PinnedResizeCorner {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

final class PinnedImageView: NSView {
    weak var controller: PinnedImageController?
    private let image: NSImage
    private var closeButton: PinnedCloseButton!

    private let cornerHitSize: CGFloat = 20.0
    private var activeCorner: PinnedResizeCorner?
    private var fixedAnchorPoint: NSPoint = .zero
    private var isHovered = false

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
        // 采用专用高对比度深色微晶玻璃关闭按钮
        closeButton = PinnedCloseButton(target: self, action: #selector(close))
        closeButton.frame = NSRect(x: bounds.maxX - 28, y: bounds.maxY - 28, width: 22, height: 22)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        closeButton.alphaValue = 0
        addSubview(closeButton)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect, .mouseMoved], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        guard bounds.width > cornerHitSize * 2, bounds.height > cornerHitSize * 2 else { return }
        let tl = NSRect(x: 0, y: bounds.maxY - cornerHitSize, width: cornerHitSize, height: cornerHitSize)
        let tr = NSRect(x: bounds.maxX - cornerHitSize, y: bounds.maxY - cornerHitSize, width: cornerHitSize, height: cornerHitSize)
        let bl = NSRect(x: 0, y: 0, width: cornerHitSize, height: cornerHitSize)
        let br = NSRect(x: bounds.maxX - cornerHitSize, y: 0, width: cornerHitSize, height: cornerHitSize)

        addCursorRect(tl, cursor: ScreenshotCursorFactory.resizeDiagonalNWSE)
        addCursorRect(tr, cursor: ScreenshotCursorFactory.resizeDiagonalNESW)
        addCursorRect(bl, cursor: ScreenshotCursorFactory.resizeDiagonalNESW)
        addCursorRect(br, cursor: ScreenshotCursorFactory.resizeDiagonalNWSE)
    }

    private func cornerAt(point: NSPoint) -> PinnedResizeCorner? {
        guard bounds.width > cornerHitSize * 2, bounds.height > cornerHitSize * 2 else { return nil }
        // 关闭按钮绝对优先
        if closeButton.frame.contains(point) { return nil }

        let tl = NSRect(x: 0, y: bounds.maxY - cornerHitSize, width: cornerHitSize, height: cornerHitSize)
        let tr = NSRect(x: bounds.maxX - cornerHitSize, y: bounds.maxY - cornerHitSize, width: cornerHitSize, height: cornerHitSize)
        let bl = NSRect(x: 0, y: 0, width: cornerHitSize, height: cornerHitSize)
        let br = NSRect(x: bounds.maxX - cornerHitSize, y: 0, width: cornerHitSize, height: cornerHitSize)

        if tl.contains(point) { return .topLeft }
        if tr.contains(point) { return .topRight }
        if bl.contains(point) { return .bottomLeft }
        if br.contains(point) { return .bottomRight }
        return nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1,
                   respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])

        // 悬停时在四角绘制精致微晶角标，提示可拉动缩放
        if isHovered || activeCorner != nil {
            drawCornerIndicators()
        }
    }

    private func drawCornerIndicators() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.65).cgColor)
        ctx.setLineWidth(2.0)
        ctx.setLineCap(.round)

        let len: CGFloat = 8.0
        let pad: CGFloat = 4.0

        // Top-Left
        ctx.move(to: CGPoint(x: pad, y: bounds.maxY - pad - len))
        ctx.addLine(to: CGPoint(x: pad, y: bounds.maxY - pad))
        ctx.addLine(to: CGPoint(x: pad + len, y: bounds.maxY - pad))

        // Bottom-Left
        ctx.move(to: CGPoint(x: pad, y: pad + len))
        ctx.addLine(to: CGPoint(x: pad, y: pad))
        ctx.addLine(to: CGPoint(x: pad + len, y: pad))

        // Bottom-Right
        ctx.move(to: CGPoint(x: bounds.maxX - pad - len, y: pad))
        ctx.addLine(to: CGPoint(x: bounds.maxX - pad, y: pad))
        ctx.addLine(to: CGPoint(x: bounds.maxX - pad, y: pad + len))

        ctx.strokePath()
        ctx.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // 优先判断四角拖拽：固定对角绝对锚点
        if let corner = cornerAt(point: point), let window {
            activeCorner = corner
            switch corner {
            case .topLeft:
                fixedAnchorPoint = NSPoint(x: window.frame.maxX, y: window.frame.minY)
            case .topRight:
                fixedAnchorPoint = NSPoint(x: window.frame.minX, y: window.frame.minY)
            case .bottomLeft:
                fixedAnchorPoint = NSPoint(x: window.frame.maxX, y: window.frame.maxY)
            case .bottomRight:
                fixedAnchorPoint = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            }
            return
        }

        if event.clickCount == 2 {
            window?.zoom(nil)
        } else {
            window?.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let corner = activeCorner, let window = self.window else { return }
        let mouse = NSEvent.mouseLocation
        let anchor = fixedAnchorPoint

        // 计算当前鼠标相对于固定对角锚点的水平与垂直绝对物理跨度
        let spanX: CGFloat
        let spanY: CGFloat

        switch corner {
        case .topLeft:
            spanX = anchor.x - mouse.x
            spanY = mouse.y - anchor.y
        case .topRight:
            spanX = mouse.x - anchor.x
            spanY = mouse.y - anchor.y
        case .bottomLeft:
            spanX = anchor.x - mouse.x
            spanY = anchor.y - mouse.y
        case .bottomRight:
            spanX = mouse.x - anchor.x
            spanY = anchor.y - mouse.y
        }

        let aspectRatio = image.size.width / max(1.0, image.size.height)
        // 直接由鼠标绝对跨度计算等比新尺寸，绝无单向缩小或死锁累积误差
        let rawWidth = max(spanX, spanY * aspectRatio)
        let clampedWidth = min(2560.0, max(120.0, rawWidth))
        let clampedHeight = clampedWidth / aspectRatio

        let finalWidth: CGFloat
        let finalHeight: CGFloat
        if clampedHeight < 80.0 {
            finalHeight = 80.0
            finalWidth = finalHeight * aspectRatio
        } else if clampedHeight > 1800.0 {
            finalHeight = 1800.0
            finalWidth = finalHeight * aspectRatio
        } else {
            finalWidth = clampedWidth
            finalHeight = clampedHeight
        }

        let newFrame: NSRect
        switch corner {
        case .topLeft:
            newFrame = NSRect(x: anchor.x - finalWidth, y: anchor.y, width: finalWidth, height: finalHeight)
        case .topRight:
            newFrame = NSRect(x: anchor.x, y: anchor.y, width: finalWidth, height: finalHeight)
        case .bottomLeft:
            newFrame = NSRect(x: anchor.x - finalWidth, y: anchor.y - finalHeight, width: finalWidth, height: finalHeight)
        case .bottomRight:
            newFrame = NSRect(x: anchor.x, y: anchor.y - finalHeight, width: finalWidth, height: finalHeight)
        }

        window.setFrame(newFrame, display: true, animate: false)
    }

    override func mouseUp(with event: NSEvent) {
        if activeCorner != nil {
            activeCorner = nil
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    /// 关键改动：原生支持 macOS 触摸板双指捏合（Pinch-to-zoom）平滑缩放
    override func magnify(with event: NSEvent) {
        let factor = 1.0 + event.magnification
        controller?.resize(by: factor)
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : (event.scrollingDeltaY > 0 ? 0.05 : -0.05)
            controller?.adjustOpacity(by: delta)
            return
        }

        let deltaY = event.scrollingDeltaY
        // 过滤微小抖动死区，防止触摸板停止惯性产生抖动缩小
        guard abs(deltaY) > 0.1 else { return }

        let factor: CGFloat
        if event.hasPreciseScrollingDeltas {
            // 触摸板平滑滚动
            factor = 1.0 + (deltaY * 0.008)
        } else {
            // 传统鼠标滚轮阶梯滚动
            factor = deltaY > 0 ? 1.08 : 0.92
        }
        controller?.resize(by: max(0.5, min(1.5, factor)))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
        NSAnimationContext.runAnimationGroup { _ in closeButton.animator().alphaValue = 1.0 }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
        NSAnimationContext.runAnimationGroup { _ in closeButton.animator().alphaValue = 0 }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let opacity = NSMenuItem(title: "恢复不透明", action: #selector(resetOpacity), keyEquivalent: "")
        opacity.target = self
        menu.addItem(opacity)
        menu.addItem(.separator())
        let close = NSMenuItem(title: "关闭贴图", action: #selector(self.close), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func resetOpacity() { controller?.panel.alphaValue = 1 }
    @objc private func close() { controller?.close() }
}

/// 贴图窗口右上角高对比度关闭按钮：深色底衬 + 纯白高亮 xmark + 悬停鲜红警告
private final class PinnedCloseButton: NSButton {
    private var isHovered = false
    private var trackingAreaRef: NSTrackingArea?

    init(target: AnyObject?, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        self.target = target
        self.action = action
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.6
        layer?.shadowRadius = 4
        layer?.shadowOffset = NSSize(width: 0, height: -1)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    // 关键改动：不透明深色背景打底并绘制清晰纯白 10pt xmark，杜绝因透明切口而看不清
    override func draw(_ dirtyRect: NSRect) {
        let circlePath = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
        if isHovered {
            NSColor(red: 235 / 255, green: 55 / 255, blue: 55 / 255, alpha: 0.95).setFill()
            circlePath.fill()
            NSColor.white.withAlphaComponent(0.45).setStroke()
        } else {
            NSColor(red: 20 / 255, green: 22 / 255, blue: 28 / 255, alpha: 0.90).setFill()
            circlePath.fill()
            NSColor.white.withAlphaComponent(0.35).setStroke()
        }
        circlePath.lineWidth = 1.0
        circlePath.stroke()

        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        if let xmark = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")?.withSymbolConfiguration(config) {
            let iconSize = NSSize(width: 10, height: 10)
            let iconRect = NSRect(
                x: bounds.midX - iconSize.width / 2,
                y: bounds.midY - iconSize.height / 2,
                width: iconSize.width,
                height: iconSize.height
            )
            let tinted = xmark.copy() as! NSImage
            tinted.lockFocus()
            NSColor.white.set()
            NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
            tinted.unlockFocus()
            tinted.draw(in: iconRect)
        }
    }
}

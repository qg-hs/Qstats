import AppKit

final class PinnedPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PinnedImageController: NSObject, NSWindowDelegate {
    let panel: PinnedPanel
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
        panel = PinnedPanel(contentRect: NSRect(origin: origin, size: initial),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        imageView = PinnedImageView(image: image)
        super.init()
        panel.delegate = self
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // 关键改动：禁用系统背景拖动，杜绝与四角缩放及平移拖动竞争导致的剧烈抖动
        panel.isMovableByWindowBackground = false
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

    private let cornerHitSize: CGFloat = 24.0
    private var activeCorner: PinnedResizeCorner?
    private var hoveredCorner: PinnedResizeCorner?
    private var fixedAnchorPoint: NSPoint = .zero
    private var isHovered = false
    private var trackingAreaRef: NSTrackingArea?

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
        // 采用专用高对比度深色微晶玻璃关闭按钮，略微内嵌以避让右上角拉伸手柄
        closeButton = PinnedCloseButton(target: self, action: #selector(close))
        closeButton.frame = NSRect(x: bounds.maxX - 30, y: bounds.maxY - 30, width: 20, height: 20)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        closeButton.alphaValue = 0
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // 关键改动：动态注册全视口鼠标追踪区，持续派发 mouseMoved 实现实时光标与角标高亮
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = trackingAreaRef {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

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

        // 悬停或拖动时在四角绘制微晶指示角标与激活状态
        if isHovered || activeCorner != nil {
            drawCornerIndicators()
        }
    }

    // 关键改动：完整绘制四角 L 型手柄，并在鼠标 hover 对应角时给予青绿色高亮与小圆点反馈
    private func drawCornerIndicators() {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()

        let len: CGFloat = 10.0
        let pad: CGFloat = 3.0

        let corners: [(PinnedResizeCorner, CGPoint, CGPoint, CGPoint)] = [
            (.topLeft,
             CGPoint(x: pad, y: bounds.maxY - pad - len),
             CGPoint(x: pad, y: bounds.maxY - pad),
             CGPoint(x: pad + len, y: bounds.maxY - pad)),
            (.topRight,
             CGPoint(x: bounds.maxX - pad - len, y: bounds.maxY - pad),
             CGPoint(x: bounds.maxX - pad, y: bounds.maxY - pad),
             CGPoint(x: bounds.maxX - pad, y: bounds.maxY - pad - len)),
            (.bottomLeft,
             CGPoint(x: pad, y: pad + len),
             CGPoint(x: pad, y: pad),
             CGPoint(x: pad + len, y: pad)),
            (.bottomRight,
             CGPoint(x: bounds.maxX - pad - len, y: pad),
             CGPoint(x: bounds.maxX - pad, y: pad),
             CGPoint(x: bounds.maxX - pad, y: pad + len))
        ]

        for (corner, p1, p2, p3) in corners {
            let isCornerActive = (activeCorner == corner || hoveredCorner == corner)
            let strokeColor = isCornerActive
                ? ScreenshotDesignTokens.iconPrimary.cgColor
                : NSColor.white.withAlphaComponent(0.65).cgColor
            let lineWidth: CGFloat = isCornerActive ? 2.5 : 1.5

            ctx.saveGState()
            ctx.setStrokeColor(strokeColor)
            ctx.setLineWidth(lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // 投影增强可见度
            ctx.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor.black.withAlphaComponent(0.7).cgColor)

            ctx.move(to: p1)
            ctx.addLine(to: p2)
            ctx.addLine(to: p3)
            ctx.strokePath()

            if isCornerActive {
                // 高亮小圆点提示激活状态
                let dotSize: CGFloat = 5.0
                let dotRect = CGRect(x: p2.x - dotSize / 2, y: p2.y - dotSize / 2, width: dotSize, height: dotSize)
                ctx.setFillColor(ScreenshotDesignTokens.iconPrimary.cgColor)
                ctx.fillEllipse(in: dotRect)
            }
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        let point = convert(event.locationInWindow, from: nil)
        let corner = cornerAt(point: point)
        if corner != hoveredCorner {
            hoveredCorner = corner
            needsDisplay = true
        }

        // 关键改动：无需等待窗口激活，直接响应四角对角缩放光标与关闭按钮光标
        switch corner {
        case .topLeft, .bottomRight:
            ScreenshotCursorFactory.resizeDiagonalNWSE.set()
        case .topRight, .bottomLeft:
            ScreenshotCursorFactory.resizeDiagonalNESW.set()
        case .none:
            if closeButton.frame.contains(point) {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
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
            needsDisplay = true
            return
        }

        if event.clickCount == 2 {
            window?.zoom(nil)
        } else {
            // 关键改动：仅在点击图片主体区域时触发平滑窗口拖动，与四角拉伸彻底隔离
            window?.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let corner = activeCorner, let window = self.window else { return }
        let mouse = NSEvent.mouseLocation
        let anchor = fixedAnchorPoint

        // 关键改动：对角线正交投影数学算法，单向连续缩放，彻底根除死锁与剧烈抖动
        let signX: CGFloat
        let signY: CGFloat
        switch corner {
        case .topLeft:     signX = -1.0; signY =  1.0
        case .topRight:    signX =  1.0; signY =  1.0
        case .bottomLeft:  signX = -1.0; signY = -1.0
        case .bottomRight: signX =  1.0; signY = -1.0
        }

        let dx = (mouse.x - anchor.x) * signX
        let dy = (mouse.y - anchor.y) * signY
        let aspectRatio = image.size.width / max(1.0, image.size.height)

        // 沿对角线投影计算目标高度
        let projHeight = (dx * aspectRatio + dy * 1.0) / (aspectRatio * aspectRatio + 1.0)
        let clampedHeight = min(1800.0, max(80.0, projHeight))
        let clampedWidth = min(2560.0, max(120.0, clampedHeight * aspectRatio))
        let finalHeight = clampedWidth / aspectRatio
        let finalWidth = clampedWidth

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
            let point = convert(event.locationInWindow, from: nil)
            hoveredCorner = cornerAt(point: point)
            window?.invalidateCursorRects(for: self)
            needsDisplay = true
        }
    }

    /// 原生支持 macOS 触摸板双指捏合（Pinch-to-zoom）平滑缩放
    override func magnify(with event: NSEvent) {
        let factor = 1.0 + event.magnification
        controller?.resize(by: factor)
    }

    // 关键改动：兼容高精触摸板与普通鼠标滚轮 deltaY，且不向底层视图泄漏事件引发背景滚动条
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : (event.scrollingDeltaY > 0 ? 0.05 : -0.05)
            controller?.adjustOpacity(by: delta)
            return
        }

        let deltaY: CGFloat
        if event.hasPreciseScrollingDeltas {
            deltaY = event.scrollingDeltaY
        } else if abs(event.scrollingDeltaY) > 0.001 {
            deltaY = event.scrollingDeltaY
        } else {
            deltaY = event.deltaY * 6.0
        }

        guard abs(deltaY) > 0.05 else { return }

        let factor: CGFloat
        if event.hasPreciseScrollingDeltas {
            factor = 1.0 + (deltaY * 0.006)
        } else {
            factor = deltaY > 0 ? 1.08 : 0.92
        }
        controller?.resize(by: max(0.5, min(1.5, factor)))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        let point = convert(event.locationInWindow, from: nil)
        hoveredCorner = cornerAt(point: point)
        needsDisplay = true
        NSAnimationContext.runAnimationGroup { _ in closeButton.animator().alphaValue = 1.0 }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        hoveredCorner = nil
        needsDisplay = true
        NSCursor.arrow.set()
        NSAnimationContext.runAnimationGroup { _ in closeButton.animator().alphaValue = 0 }
    }

    override func keyDown(with event: NSEvent) {
        // Esc 快捷退出贴图
        if event.keyCode == 53 {
            close()
            return
        }
        // ⌘+C 复制贴图图像到剪贴板
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
            if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .png, properties: [:]) {
                let item = NSPasteboardItem()
                item.setData(data, forType: .png)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([item])
            }
            return
        }
        super.keyDown(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let opacity = NSMenuItem(title: "恢复不透明", action: #selector(resetOpacity), keyEquivalent: "")
        opacity.target = self
        menu.addItem(opacity)
        menu.addItem(.separator())
        let close = NSMenuItem(title: "关闭贴图 (Esc)", action: #selector(self.close), keyEquivalent: "")
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
        super.init(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        self.target = target
        self.action = action
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 10
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

        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        if let xmark = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")?.withSymbolConfiguration(config) {
            let iconSize = NSSize(width: 9, height: 9)
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


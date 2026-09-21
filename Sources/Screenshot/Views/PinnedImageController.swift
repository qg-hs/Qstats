import AppKit

final class PinnedImageController: NSObject, NSWindowDelegate {
    let panel: NSPanel
    private let imageView: PinnedImageView
    var onClose: (() -> Void)?

    init(image: NSImage, near point: NSPoint? = nil) {
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
        let proposed = NSSize(width: min(1600, max(120, current.width * factor)),
                              height: min(1200, max(80, current.height * factor)))
        let center = NSPoint(x: current.midX, y: current.midY)
        panel.setFrame(NSRect(x: center.x - proposed.width / 2, y: center.y - proposed.height / 2,
                              width: proposed.width, height: proposed.height), display: true, animate: false)
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

final class PinnedImageView: NSView {
    weak var controller: PinnedImageController?
    private let image: NSImage
    private var closeButton: PinnedCloseButton!

    init(image: NSImage) {
        self.image = image
        super.init(frame: NSRect(origin: .zero, size: image.size))
        // 关键改动：采用专用高对比度深色微晶玻璃关闭按钮，杜绝与任何截图背景同色导致的隐形问题
        closeButton = PinnedCloseButton(target: self, action: #selector(close))
        closeButton.frame = NSRect(x: bounds.maxX - 28, y: bounds.maxY - 28, width: 22, height: 22)
        closeButton.autoresizingMask = [.minXMargin, .minYMargin]
        closeButton.alphaValue = 0
        addSubview(closeButton)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1,
                   respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.zoom(nil) }
        else { window?.performDrag(with: event) }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            controller?.adjustOpacity(by: event.scrollingDeltaY > 0 ? 0.05 : -0.05)
        } else {
            controller?.resize(by: event.scrollingDeltaY > 0 ? 1.08 : 0.92)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { _ in closeButton.animator().alphaValue = 1.0 }
    }

    override func mouseExited(with event: NSEvent) {
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

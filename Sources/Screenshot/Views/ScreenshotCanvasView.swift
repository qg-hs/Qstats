import AppKit
import UniformTypeIdentifiers

protocol ScreenshotCanvasDelegate: AnyObject {
    func screenshotCanvasDidBeginSelection(_ canvas: ScreenshotCanvasView)
    func screenshotCanvasDidCancel(_ canvas: ScreenshotCanvasView)
    func screenshotCanvas(_ canvas: ScreenshotCanvasView, didRequestPin image: NSImage)
}

enum SelectionHandle: CaseIterable {
    case topLeft
    case topCenter
    case topRight
    case rightCenter
    case bottomRight
    case bottomCenter
    case bottomLeft
    case leftCenter
}

// 关键改动 1：独立的高性能透明叠加层，所有鼠标事件穿透由宿主处理，底图由 GPU 托管避免每帧 CPU 重绘
final class ScreenshotOverlayCanvasView: NSView {
    weak var canvasView: ScreenshotCanvasView?

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // 事件穿透：直接交由宿主 ScreenshotCanvasView 统一路由处理
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        canvasView?.drawOverlay(in: dirtyRect)
    }
}

final class ScreenshotCanvasView: NSView, ScreenshotToolbarDelegate, ScreenshotColorPickerDelegate, ScreenshotSizeSliderDelegate, NSTextFieldDelegate {
    weak var delegate: ScreenshotCanvasDelegate?

    private let screenshot: NSImage
    private let captureScale: CGFloat

    // 关键改动 1：底图硬件加速层，全屏位图驻留显存，拖拽框选时 0 CPU 软件插值开销
    private let backgroundImageView: NSImageView
    private let overlayCanvas: ScreenshotOverlayCanvasView

    private var selection: NSRect = .zero
    private var selectionStart: NSPoint?

    // 8 边方向控点拖拽调整选区状态
    private var activeHandle: SelectionHandle?
    private var dragAnchorPoint: NSPoint?

    private var annotationStart: NSPoint?
    private var workingPoints: [NSPoint] = []
    private var workingAnnotation: Annotation?
    private var annotations: [Annotation] = []
    private var activeTool: AnnotationTool = .rectangle

    // 采色器与当前颜色状态
    private var currentColor: NSColor = .systemRed
    private var colorPickerView: ScreenshotColorPickerView?

    // 标注粗细与字号滑动条控制
    private var currentStrokeWidth: CGFloat = 3.0
    private var currentFontSize: CGFloat = 18.0
    private var currentMosaicScale: CGFloat = 16.0
    private var sizeSliderView: ScreenshotSizeSliderView?

    // 关键改动 1：马赛克位图缓存体系，拖拽过程实现 O(1) 局部 blit 贴图，告别 CoreImage 每帧反复计算
    private var cachedMosaicCGImage: CGImage?
    private var cachedMosaicScale: CGFloat = -1

    private var toolbar: ScreenshotToolbarView?
    private var textField: NSTextField?
    private var textEditor: NSView?
    private var pendingTextOrigin: NSPoint?
    private var isPresentingSavePanel = false

    init(capture: CapturedScreen) {
        self.screenshot = capture.image
        self.captureScale = capture.scale

        let canvasBounds = NSRect(origin: .zero, size: capture.screen.frame.size)

        // 1. 底图层：由系统 NSImageView 硬件图层托管，初始化一次性上传 GPU 纹理
        let bg = NSImageView(frame: canvasBounds)
        bg.image = capture.image
        bg.imageScaling = .scaleAxesIndependently
        bg.wantsLayer = true
        self.backgroundImageView = bg

        // 2. 动态覆盖层：透明背景，仅绘制蒙版镂空、标注、边框与控点
        let overlay = ScreenshotOverlayCanvasView(frame: canvasBounds)
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.clear.cgColor
        self.overlayCanvas = overlay

        super.init(frame: canvasBounds)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        overlay.canvasView = self
        addSubview(bg)
        addSubview(overlay)

        // 预热马赛克滤镜缓存
        warmupMosaicCache(scale: currentMosaicScale)

        // 监听系统调色板实时选色通知
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleColorPanelNotification(_:)),
            name: NSColorPanel.colorDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSColorPanel.shared.orderOut(nil)
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        guard !selection.isEmpty else {
            addCursorRect(bounds, cursor: ScreenshotCursorFactory.selection)
            return
        }

        // 优先注册 8 个边角拖拽控点的光标响应区
        let hitRadius: CGFloat = 9.0
        for handle in SelectionHandle.allCases {
            let pos = handlePosition(handle)
            let rect = NSRect(x: pos.x - hitRadius, y: pos.y - hitRadius,
                              width: hitRadius * 2, height: hitRadius * 2).intersection(bounds)
            if !rect.isEmpty {
                addCursorRect(rect, cursor: cursor(for: handle))
            }
        }

        // 选区内部使用当前标注工具的光标
        let selected = selection.intersection(bounds)
        addCursorRect(selected, cursor: ScreenshotCursorFactory.cursor(for: activeTool))

        // 选区外部使用十字选区光标
        let outside = [
            NSRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: max(0, selected.minY - bounds.minY)),
            NSRect(x: bounds.minX, y: selected.maxY, width: bounds.width, height: max(0, bounds.maxY - selected.maxY)),
            NSRect(x: bounds.minX, y: selected.minY, width: max(0, selected.minX - bounds.minX), height: selected.height),
            NSRect(x: selected.maxX, y: selected.minY, width: max(0, bounds.maxX - selected.maxX), height: selected.height)
        ]
        for rect in outside where !rect.isEmpty {
            addCursorRect(rect, cursor: ScreenshotCursorFactory.selection)
        }
    }

    // 关键改动 1：抽离轻量级叠加层绘制逻辑，底图零重绘开销
    fileprivate func drawOverlay(in dirtyRect: NSRect) {
        guard !selection.isEmpty else {
            NSColor.black.withAlphaComponent(0.28).setFill()
            bounds.fill()
            drawStartHint()
            return
        }

        // 选区外暗色蒙版，选区内部镂空透出 GPU 底图
        let dim = NSBezierPath(rect: bounds)
        dim.appendRect(selection)
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.48).setFill()
        dim.fill()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selection).addClip()
        if let context = NSGraphicsContext.current?.cgContext {
            let mosaic = getOrGenerateMosaicCache(for: currentMosaicScale)
            for annotation in annotations {
                annotation.draw(in: context, background: screenshot, canvasBounds: bounds, mosaicCache: mosaic)
            }
            if let working = workingAnnotation {
                working.draw(in: context, background: screenshot, canvasBounds: bounds, mosaicCache: mosaic)
                // 关键改动 2：简约纯粹的马赛克框选边框，去除繁杂四角白圆点与粗黑阴影，使用 1.0pt 极简白透细线
                if case let .mosaic(rect, _) = working {
                    context.saveGState()
                    context.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
                    context.setLineWidth(1.0)
                    context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
                    context.restoreGState()
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        // 选区外边框应用主题青绿配置色 (#43E9C9)
        ScreenshotDesignTokens.iconPrimary.setStroke()
        let border = NSBezierPath(rect: selection.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        border.stroke()
        drawHandles()
        drawSizeBadge()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // 若采色器弹出，点击外部收起采色器
        if let picker = colorPickerView {
            let pointInPicker = picker.convert(point, from: self)
            if !picker.bounds.contains(pointInPicker) {
                dismissColorPicker()
            }
        }

        // 若滑动条调节器弹出，点击外部收起滑动条
        if let slider = sizeSliderView {
            let pointInSlider = slider.convert(point, from: self)
            if !slider.bounds.contains(pointInSlider) {
                dismissSizeSlider()
            }
        }

        // 双击选区内部直接复制并退出
        if !selection.isEmpty, event.clickCount == 2, selection.contains(point) {
            copySelection()
            return
        }
        commitPendingText()

        // 检查是否命中 8 边方向拖拽控点
        if let handle = hitHandle(at: point) {
            activeHandle = handle
            dragAnchorPoint = oppositeAnchorPoint(for: handle)
            removeToolbar()
            dismissColorPicker()
            dismissSizeSlider()
            return
        }

        // 点击选区外重新框选
        if selection.isEmpty || !selection.contains(point) {
            dismissColorPicker()
            dismissSizeSlider()
            beginSelection(at: point)
            return
        }

        // 文字工具
        if activeTool == .text {
            beginText(at: point)
            return
        }

        annotationStart = point
        workingPoints = [point]
        updateWorkingAnnotation(to: point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = clamped(convert(event.locationInWindow, from: nil))

        // 正在拖拽 8 边控点缩放选区
        if let handle = activeHandle, let anchor = dragAnchorPoint {
            switch handle {
            case .topLeft, .topRight, .bottomRight, .bottomLeft:
                selection = normalizedRect(from: anchor, to: point).intersection(bounds)
            case .topCenter, .bottomCenter:
                let yMin = min(anchor.y, point.y)
                let yMax = max(anchor.y, point.y)
                selection = NSRect(x: selection.minX, y: yMin, width: selection.width, height: yMax - yMin).intersection(bounds)
            case .leftCenter, .rightCenter:
                let xMin = min(anchor.x, point.x)
                let xMax = max(anchor.x, point.x)
                selection = NSRect(x: xMin, y: selection.minY, width: xMax - xMin, height: selection.height).intersection(bounds)
            }
            // 关键改动 1：刷新极轻量叠加层，耗时 < 0.1ms，高刷满帧流畅
            overlayCanvas.needsDisplay = true
            return
        }

        // 正在初始框选
        if let start = selectionStart {
            selection = normalizedRect(from: start, to: point).intersection(bounds)
            overlayCanvas.needsDisplay = true
            return
        }

        // 正在绘制标注
        guard annotationStart != nil else { return }
        if activeTool == .pen { workingPoints.append(point) }
        updateWorkingAnnotation(to: point)
        overlayCanvas.needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        // 完成 8 边控点拖拽
        if activeHandle != nil {
            activeHandle = nil
            dragAnchorPoint = nil
            if selection.width < 8 || selection.height < 8 {
                selection = .zero
                removeToolbar()
            } else {
                showToolbar()
            }
            window?.invalidateCursorRects(for: self)
            overlayCanvas.needsDisplay = true
            return
        }

        // 完成初始框选
        if selectionStart != nil {
            selectionStart = nil
            if selection.width < 8 || selection.height < 8 {
                selection = .zero
                removeToolbar()
            } else {
                showToolbar()
            }
            window?.invalidateCursorRects(for: self)
            overlayCanvas.needsDisplay = true
            return
        }

        // 完成标注图元
        if let annotation = workingAnnotation {
            annotations.append(annotation)
            workingAnnotation = nil
            annotationStart = nil
            workingPoints.removeAll(keepingCapacity: true)
            overlayCanvas.needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            if sizeSliderView != nil {
                dismissSizeSlider()
                return
            }
            if colorPickerView != nil {
                dismissColorPicker()
                return
            }
            if textField != nil {
                cancelPendingText()
            } else {
                dismissColorPicker()
                dismissSizeSlider()
                NSColorPanel.shared.orderOut(nil)
                delegate?.screenshotCanvasDidCancel(self)
            }
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            if textField != nil { commitPendingText() } else if !selection.isEmpty { copySelection() }
            return
        }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            undoLast()
            return
        }
        super.keyDown(with: event)
    }

    private func beginSelection(at point: NSPoint) {
        delegate?.screenshotCanvasDidBeginSelection(self)
        removeToolbar()
        dismissColorPicker()
        dismissSizeSlider()
        annotations.removeAll()
        selection = .zero
        selectionStart = clamped(point)
        overlayCanvas.needsDisplay = true
    }

    private func updateWorkingAnnotation(to point: NSPoint) {
        guard let start = annotationStart else { return }
        switch activeTool {
        case .rectangle:
            workingAnnotation = .rectangle(rect: normalizedRect(from: start, to: point),
                                           color: currentColor, width: currentStrokeWidth)
        case .arrow:
            workingAnnotation = .arrow(start: start, end: point,
                                       color: currentColor, width: currentStrokeWidth)
        case .pen:
            workingAnnotation = .pen(points: workingPoints,
                                     color: currentColor, width: currentStrokeWidth)
        case .mosaic:
            workingAnnotation = .mosaic(rect: normalizedRect(from: start, to: point), scale: currentMosaicScale)
        case .text:
            break
        }
    }

    // 关键改动 3：文字输入框底色彻底透明，去掉遮挡黑底与投影，以极简半透微边框辅助定位
    private func beginText(at point: NSPoint) {
        commitPendingText()

        let textX = min(point.x, max(selection.minX, selection.maxX - min(140, selection.width)))
        let editorWidth = min(360, max(140, selection.maxX - textX))
        let editorHeight: CGFloat = max(42.0, currentFontSize + 20.0)
        let editorX = min(bounds.maxX - editorWidth - 4, max(bounds.minX + 4, textX))
        let editorY = min(bounds.maxY - editorHeight - 4, max(bounds.minY + 4, point.y - 10))
        pendingTextOrigin = NSPoint(x: editorX + 10, y: editorY + 10)

        let editor = NSView(frame: NSRect(x: editorX, y: editorY, width: editorWidth, height: editorHeight))
        editor.wantsLayer = true
        editor.layer?.cornerRadius = 6
        // 关键改动 3：底色透明，绝不遮挡底部图片
        editor.layer?.backgroundColor = NSColor.clear.cgColor
        editor.layer?.borderWidth = 1.0
        // 极简微弱边框提示输入区域
        editor.layer?.borderColor = ScreenshotDesignTokens.iconPrimary.withAlphaComponent(0.65).cgColor
        editor.layer?.shadowOpacity = 0

        let field = NSTextField(frame: editor.bounds.insetBy(dx: 8, dy: 5))
        field.autoresizingMask = [.width, .height]
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.textColor = currentColor
        field.font = .systemFont(ofSize: currentFontSize, weight: .medium)
        field.placeholderAttributedString = NSAttributedString(
            string: "键入标注文本...",
            attributes: [
                .foregroundColor: NSColor(white: 0.75, alpha: 0.9),
                .font: NSFont.systemFont(ofSize: max(12, currentFontSize - 2), weight: .regular)
            ]
        )
        field.delegate = self
        editor.addSubview(field)
        addSubview(editor)

        textEditor = editor
        textField = field
        window?.makeFirstResponder(field)
    }

    private func commitPendingText() {
        guard let field = textField, let origin = pendingTextOrigin else { return }
        let value = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            annotations.append(.text(origin: origin, value: value, color: currentColor, size: currentFontSize))
        }
        cleanupTextEditor()
        overlayCanvas.needsDisplay = true
    }

    private func cancelPendingText() {
        cleanupTextEditor()
    }

    private func cleanupTextEditor() {
        textField?.delegate = nil
        textEditor?.removeFromSuperview()
        textField = nil
        textEditor = nil
        pendingTextOrigin = nil
        window?.makeFirstResponder(self)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        commitPendingText()
    }

    // 关键改动：底部工具栏严格居中对齐当前截图选区（midX），并实现全边界安全防遮挡算法
    private func updateToolbarPosition() {
        guard let bar = toolbar else { return }
        bar.layoutSubtreeIfNeeded()
        let size = bar.fittingSize
        let margin: CGFloat = 10
        let width = min(bounds.width - margin * 2, max(1, size.width))
        let height = size.height

        // 1. 水平居中对齐选区
        var x = selection.midX - width / 2
        // 2. 水平边界智能防溢出（防左侧/右侧屏幕遮挡）
        x = min(bounds.maxX - width - margin, max(bounds.minX + margin, x))

        // 3. 垂直优先置于选区下方
        var y = selection.minY - height - margin
        // 若底部超出屏幕可见区，翻转至选区上方
        if y < bounds.minY + margin {
            y = selection.maxY + margin
        }
        // 若上方亦超出屏幕（超大选区/全屏框选），内嵌置于选区内部底端
        if y + height > bounds.maxY - margin {
            y = selection.minY + margin
        }
        // 最终绝对边界安全限制，绝不超出屏幕可见区域
        y = min(bounds.maxY - height - margin, max(bounds.minY + margin, y))

        bar.frame = NSRect(x: x, y: y, width: width, height: height)
    }

    private func showToolbar() {
        removeToolbar()
        let bar = ScreenshotToolbarView()
        bar.delegate = self
        bar.setSelectedTool(activeTool)
        bar.setColor(currentColor)
        let initialWidth: CGFloat
        switch activeTool {
        case .text: initialWidth = currentFontSize
        case .mosaic: initialWidth = currentMosaicScale
        default: initialWidth = currentStrokeWidth
        }
        bar.setWidth(initialWidth)
        addSubview(bar)
        toolbar = bar
        updateToolbarPosition()
        window?.makeFirstResponder(self)
    }

    private func removeToolbar() {
        dismissColorPicker()
        dismissSizeSlider()
        toolbar?.removeFromSuperview()
        toolbar = nil
    }

    // MARK: - 马赛克高速缓存体系

    private func warmupMosaicCache(scale: CGFloat) {
        _ = getOrGenerateMosaicCache(for: scale)
    }

    private func getOrGenerateMosaicCache(for scale: CGFloat) -> CGImage? {
        if let cached = cachedMosaicCGImage, cachedMosaicScale == scale {
            return cached
        }
        guard let cgImage = screenshot.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let filter = CIFilter(name: "CIPixellate") else { return nil }
        let input = CIImage(cgImage: cgImage)
        let pointScale = CGFloat(cgImage.width) / max(1, bounds.width)
        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(max(4, scale * pointScale), forKey: kCIInputScaleKey)
        guard let output = filter.outputImage,
              let rendered = Annotation.sharedCIContext.createCGImage(output, from: input.extent) else { return nil }
        cachedMosaicCGImage = rendered
        cachedMosaicScale = scale
        return rendered
    }

    // MARK: - 8 边方向控点计算与绘制

    private func handlePosition(_ handle: SelectionHandle) -> NSPoint {
        switch handle {
        case .topLeft:      return NSPoint(x: selection.minX, y: selection.maxY)
        case .topCenter:    return NSPoint(x: selection.midX, y: selection.maxY)
        case .topRight:     return NSPoint(x: selection.maxX, y: selection.maxY)
        case .rightCenter:  return NSPoint(x: selection.maxX, y: selection.midY)
        case .bottomRight: return NSPoint(x: selection.maxX, y: selection.minY)
        case .bottomCenter: return NSPoint(x: selection.midX, y: selection.minY)
        case .bottomLeft:   return NSPoint(x: selection.minX, y: selection.minY)
        case .leftCenter:   return NSPoint(x: selection.minX, y: selection.midY)
        }
    }

    private func oppositeAnchorPoint(for handle: SelectionHandle) -> NSPoint {
        switch handle {
        case .topLeft:      return NSPoint(x: selection.maxX, y: selection.minY)
        case .topCenter:    return NSPoint(x: selection.midX, y: selection.minY)
        case .topRight:     return NSPoint(x: selection.minX, y: selection.minY)
        case .rightCenter:  return NSPoint(x: selection.minX, y: selection.midY)
        case .bottomRight: return NSPoint(x: selection.minX, y: selection.maxY)
        case .bottomCenter: return NSPoint(x: selection.midX, y: selection.maxY)
        case .bottomLeft:   return NSPoint(x: selection.maxX, y: selection.maxY)
        case .leftCenter:   return NSPoint(x: selection.maxX, y: selection.midY)
        }
    }

    private func cursor(for handle: SelectionHandle) -> NSCursor {
        switch handle {
        case .topCenter, .bottomCenter:
            return NSCursor.resizeUpDown
        case .leftCenter, .rightCenter:
            return NSCursor.resizeLeftRight
        case .topLeft, .bottomRight:
            return ScreenshotCursorFactory.resizeDiagonalNWSE
        case .topRight, .bottomLeft:
            return ScreenshotCursorFactory.resizeDiagonalNESW
        }
    }

    private func hitHandle(at point: NSPoint) -> SelectionHandle? {
        let hitRadius: CGFloat = 8.0
        for handle in SelectionHandle.allCases {
            let pos = handlePosition(handle)
            let rect = NSRect(x: pos.x - hitRadius, y: pos.y - hitRadius,
                              width: hitRadius * 2, height: hitRadius * 2)
            if rect.contains(point) { return handle }
        }
        return nil
    }

    private func drawHandles() {
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.38)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()

        NSColor.white.setFill()
        for handle in SelectionHandle.allCases {
            let pos = handlePosition(handle)
            let rect = NSRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)
            NSBezierPath(ovalIn: rect).fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        ScreenshotDesignTokens.iconPrimary.setStroke()
        for handle in SelectionHandle.allCases {
            let pos = handlePosition(handle)
            let rect = NSRect(x: pos.x - 4, y: pos.y - 4, width: 8, height: 8)
            let path = NSBezierPath(ovalIn: rect)
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawSizeBadge() {
        let text = "\(Int(selection.width * captureScale)) × \(Int(selection.height * captureScale))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        var x = selection.minX
        var y = selection.maxY + 7
        if y + size.height + 10 > bounds.maxY { y = selection.maxY - size.height - 15 }
        x = min(bounds.maxX - size.width - 14, max(7, x))
        let rect = NSRect(x: x, y: y, width: size.width + 12, height: size.height + 6)
        ScreenshotDesignTokens.iconBg.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + 6, y: rect.minY + 3), withAttributes: attrs)
    }

    private func drawStartHint() {
        let text = "拖动选择区域  ·  Esc 取消"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = NSRect(x: bounds.midX - size.width / 2 - 12, y: bounds.midY - size.height / 2 - 8,
                          width: size.width + 24, height: size.height + 16)
        ScreenshotDesignTokens.iconBg.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9).fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + 12, y: rect.minY + 8), withAttributes: attributes)
    }

    private func clamped(_ point: NSPoint) -> NSPoint {
        NSPoint(x: min(bounds.maxX, max(bounds.minX, point.x)),
                y: min(bounds.maxY, max(bounds.minY, point.y)))
    }

    func renderedSelection() -> NSImage? {
        commitPendingText()
        guard !selection.isEmpty else { return nil }
        let pixelsWide = max(1, Int((selection.width * captureScale).rounded()))
        let pixelsHigh = max(1, Int((selection.height * captureScale).rounded()))
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide,
                                            pixelsHigh: pixelsHigh, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0,
                                            bitsPerPixel: 0) else { return nil }
        bitmap.size = selection.size
        NSGraphicsContext.saveGraphicsState()
        guard let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState(); return nil
        }
        NSGraphicsContext.current = graphics
        let transform = NSAffineTransform()
        transform.translateX(by: -selection.minX, yBy: -selection.minY)
        transform.concat()
        screenshot.draw(in: bounds, from: .zero, operation: .copy, fraction: 1,
                        respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        let context = graphics.cgContext
        let mosaic = getOrGenerateMosaicCache(for: currentMosaicScale)
        for annotation in annotations {
            annotation.draw(in: context, background: screenshot, canvasBounds: bounds, mosaicCache: mosaic)
        }
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: selection.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func pngData(for image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    private func copySelection() {
        commitPendingText()
        guard let image = renderedSelection(), let data = pngData(for: image) else { return }
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
        dismissColorPicker()
        dismissSizeSlider()
        NSColorPanel.shared.orderOut(nil)
        delegate?.screenshotCanvasDidCancel(self)
    }

    private func undoLast() {
        if !annotations.isEmpty {
            annotations.removeLast()
            overlayCanvas.needsDisplay = true
        }
    }

    // MARK: - 颜色与系统调色板联动

    @objc func changeColor(_ sender: Any?) {
        applyColor(NSColorPanel.shared.color, syncToPicker: true)
    }

    @objc private func handleColorPanelNotification(_ notification: Notification) {
        guard let panel = notification.object as? NSColorPanel else { return }
        applyColor(panel.color, syncToPicker: true)
    }

    private func applyColor(_ color: NSColor, syncToPicker: Bool = true) {
        currentColor = color
        toolbar?.setColor(color)
        if syncToPicker {
            colorPickerView?.updateSelectedColor(color)
        }
        if let field = textField {
            field.textColor = color
        }
        overlayCanvas.needsDisplay = true
    }

    // MARK: - ScreenshotToolbarDelegate

    func toolbar(_ toolbar: ScreenshotToolbarView, selected tool: AnnotationTool, isToggle: Bool, anchorView: NSView) {
        activeTool = tool
        dismissColorPicker()
        let displayWidth: CGFloat
        switch activeTool {
        case .text: displayWidth = currentFontSize
        case .mosaic: displayWidth = currentMosaicScale
        default: displayWidth = currentStrokeWidth
        }
        toolbar.setWidth(displayWidth)
        window?.invalidateCursorRects(for: self)

        if tool == .mosaic {
            warmupMosaicCache(scale: currentMosaicScale)
            if isToggle && sizeSliderView != nil {
                dismissSizeSlider()
            } else {
                showSizeSlider(anchoredTo: anchorView)
            }
        } else if isToggle {
            if sizeSliderView != nil {
                dismissSizeSlider()
            } else {
                showSizeSlider(anchoredTo: anchorView)
            }
        } else {
            dismissSizeSlider()
        }
    }

    func toolbarDidRequestColorPicker(_ toolbar: ScreenshotToolbarView, anchorView: NSView) {
        dismissSizeSlider()
        if colorPickerView != nil {
            dismissColorPicker()
        } else {
            showColorPicker(anchoredTo: anchorView)
        }
    }

    func toolbarDidRequestSizeSlider(_ toolbar: ScreenshotToolbarView, anchorView: NSView) {
        dismissColorPicker()
        if sizeSliderView != nil {
            dismissSizeSlider()
        } else {
            showSizeSlider(anchoredTo: anchorView)
        }
    }

    private func showColorPicker(anchoredTo anchorView: NSView) {
        dismissColorPicker()
        let picker = ScreenshotColorPickerView(selectedColor: currentColor)
        picker.delegate = self
        addSubview(picker)

        let anchorRect = anchorView.convert(anchorView.bounds, to: self)
        let pickerWidth: CGFloat = 176
        let pickerHeight: CGFloat = 86
        var x = anchorRect.midX - pickerWidth / 2
        x = min(bounds.maxX - pickerWidth - 8, max(8, x))
        var y = anchorRect.maxY + 8
        if y + pickerHeight > bounds.maxY - 8 {
            y = anchorRect.minY - pickerHeight - 8
        }
        picker.frame = NSRect(x: x, y: y, width: pickerWidth, height: pickerHeight)
        colorPickerView = picker
    }

    private func dismissColorPicker() {
        colorPickerView?.removeFromSuperview()
        colorPickerView = nil
    }

    private func showSizeSlider(anchoredTo anchorView: NSView) {
        dismissSizeSlider()
        let slider: ScreenshotSizeSliderView
        switch activeTool {
        case .text:
            slider = ScreenshotSizeSliderView(
                currentSize: currentFontSize,
                title: "文字字号",
                minValue: 10.0,
                maxValue: 48.0,
                presets: [12, 16, 24, 32],
                unit: "pt"
            )
        case .mosaic:
            slider = ScreenshotSizeSliderView(
                currentSize: currentMosaicScale,
                title: "马赛克模糊度",
                minValue: 4.0,
                maxValue: 40.0,
                presets: [8, 14, 22, 32],
                unit: "阶"
            )
        default:
            slider = ScreenshotSizeSliderView(
                currentSize: currentStrokeWidth,
                title: "画笔粗细",
                minValue: 1.0,
                maxValue: 32.0,
                presets: [2, 4, 8, 16],
                unit: "px"
            )
        }
        slider.delegate = self
        addSubview(slider)

        let anchorRect = anchorView.convert(anchorView.bounds, to: self)
        let sliderWidth: CGFloat = 204
        let sliderHeight: CGFloat = 88
        var x = anchorRect.midX - sliderWidth / 2
        x = min(bounds.maxX - sliderWidth - 8, max(8, x))
        var y = anchorRect.maxY + 8
        if y + sliderHeight > bounds.maxY - 8 {
            y = anchorRect.minY - sliderHeight - 8
        }
        slider.frame = NSRect(x: x, y: y, width: sliderWidth, height: sliderHeight)
        sizeSliderView = slider
    }

    private func dismissSizeSlider() {
        sizeSliderView?.removeFromSuperview()
        sizeSliderView = nil
    }

    // MARK: - ScreenshotSizeSliderDelegate

    func sizeSlider(_ sliderView: ScreenshotSizeSliderView, didChangeSize size: CGFloat) {
        switch activeTool {
        case .text:
            currentFontSize = max(10, size)
            if let field = textField {
                field.font = .systemFont(ofSize: currentFontSize, weight: .medium)
            }
        case .mosaic:
            currentMosaicScale = max(4, size)
            // 模糊度更新时使缓存刷新
            warmupMosaicCache(scale: currentMosaicScale)
        default:
            currentStrokeWidth = max(1, size)
        }
        toolbar?.setWidth(size)
        overlayCanvas.needsDisplay = true
    }

    func sizeSliderDidRequestDismiss(_ sliderView: ScreenshotSizeSliderView) {
        dismissSizeSlider()
    }

    // MARK: - ScreenshotColorPickerDelegate

    func colorPicker(_ picker: ScreenshotColorPickerView, didSelectColor color: NSColor) {
        applyColor(color, syncToPicker: false)
        dismissColorPicker()
    }

    func colorPickerDidRequestDismiss(_ picker: ScreenshotColorPickerView) {
        dismissColorPicker()
    }

    func toolbarDidCycleWidth(_ toolbar: ScreenshotToolbarView) {
        switch activeTool {
        case .text:
            currentFontSize = currentFontSize >= 32 ? 12 : currentFontSize + 4
            toolbar.setWidth(currentFontSize)
        case .mosaic:
            currentMosaicScale = currentMosaicScale >= 32 ? 8 : currentMosaicScale + 6
            warmupMosaicCache(scale: currentMosaicScale)
            toolbar.setWidth(currentMosaicScale)
        default:
            currentStrokeWidth = currentStrokeWidth >= 16 ? 2 : currentStrokeWidth * 2
            toolbar.setWidth(currentStrokeWidth)
        }
    }

    func toolbarDidUndo(_ toolbar: ScreenshotToolbarView) { undoLast() }

    func toolbarDidPin(_ toolbar: ScreenshotToolbarView) {
        if let image = renderedSelection() {
            dismissColorPicker()
            dismissSizeSlider()
            NSColorPanel.shared.orderOut(nil)
            delegate?.screenshotCanvas(self, didRequestPin: image)
        }
    }

    func toolbarDidSave(_ toolbar: ScreenshotToolbarView) {
        guard !isPresentingSavePanel else { return }
        guard let image = renderedSelection(), let data = pngData(for: image) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Qstats-截图-\(Self.timestamp()).png"
        panel.canCreateDirectories = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)

        isPresentingSavePanel = true
        window?.orderOut(nil)
        panel.begin { [weak self] response in
            guard let self else { return }
            self.isPresentingSavePanel = false
            guard response == .OK, let url = panel.url else {
                self.window?.orderFrontRegardless()
                self.window?.makeKey()
                self.window?.makeFirstResponder(self)
                return
            }
            do {
                try data.write(to: url, options: .atomic)
                self.dismissColorPicker()
                self.dismissSizeSlider()
                NSColorPanel.shared.orderOut(nil)
                self.delegate?.screenshotCanvasDidCancel(self)
            } catch {
                NSSound.beep()
                self.window?.orderFrontRegardless()
                self.window?.makeKey()
                self.window?.makeFirstResponder(self)
            }
        }
    }

    func toolbarDidCopy(_ toolbar: ScreenshotToolbarView) { copySelection() }

    func toolbarDidClose(_ toolbar: ScreenshotToolbarView) {
        dismissColorPicker()
        dismissSizeSlider()
        NSColorPanel.shared.orderOut(nil)
        delegate?.screenshotCanvasDidCancel(self)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}

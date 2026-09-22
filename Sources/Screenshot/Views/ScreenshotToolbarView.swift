import AppKit
import QuartzCore

protocol ScreenshotToolbarDelegate: AnyObject {
    func toolbar(_ toolbar: ScreenshotToolbarView, selected tool: AnnotationTool, isToggle: Bool, anchorView: NSView)
    func toolbarDidRequestColorPicker(_ toolbar: ScreenshotToolbarView, anchorView: NSView)
    func toolbarDidRequestSizeSlider(_ toolbar: ScreenshotToolbarView, anchorView: NSView)
    func toolbarDidCycleWidth(_ toolbar: ScreenshotToolbarView)
    func toolbarDidUndo(_ toolbar: ScreenshotToolbarView)
    func toolbarDidPin(_ toolbar: ScreenshotToolbarView)
    func toolbarDidSave(_ toolbar: ScreenshotToolbarView)
    func toolbarDidCopy(_ toolbar: ScreenshotToolbarView)
    func toolbarDidClose(_ toolbar: ScreenshotToolbarView)
}

/// 截图底部主工具栏：采用深色磨砂玻璃、高对比度与严格数学对齐的正方形按钮布局
final class ScreenshotToolbarView: NSVisualEffectView {
    weak var delegate: ScreenshotToolbarDelegate?
    private var toolButtons: [AnnotationTool: ScreenshotToolbarButton] = [:]
    private let colorButton = ScreenshotToolbarButton()
    private let widthButton = ScreenshotToolbarButton()
    private var activeTooltip: ScreenshotTooltipView?
    private var currentSelectedTool: AnnotationTool = .rectangle

    init() {
        super.init(frame: .zero)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true

        // 工具栏主体外观：深炭黑磨砂半透玻璃 + 精致微白轮廓边框
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.8
        layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        layer?.backgroundColor = NSColor(red: 20.0 / 255.0, green: 23.0 / 255.0, blue: 30.0 / 255.0, alpha: 0.94).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.4
        layer?.shadowRadius = 14
        layer?.shadowOffset = NSSize(width: 0, height: -4)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 7, bottom: 6, right: 7)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // 基础图形标注工具 (统一 30x30 严格正方形)
        for tool in AnnotationTool.allCases {
            let button = makeButton(symbol: tool.symbolName, title: "\(tool.title)标注", shortcut: nil,
                                    action: #selector(selectTool(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(tool.rawValue)
            toolButtons[tool] = button
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(makeSeparator())

        // 颜色选择按钮：独立色板圆点，居中绘制
        configure(colorButton, symbol: nil, title: "画笔颜色与调色板", shortcut: nil,
                  action: #selector(openColorPicker))
        colorButton.isColorSwatchButton = true
        colorButton.swatchColor = .systemRed
        stack.addArrangedSubview(colorButton)

        // 粗细、字号与模糊度数值按钮：严格居中绘制数字
        configure(widthButton, symbol: nil, title: "粗细 / 字号 / 模糊度", shortcut: nil,
                  action: #selector(openSizeSlider))
        widthButton.buttonCustomText = "3"
        stack.addArrangedSubview(widthButton)

        stack.addArrangedSubview(makeButton(symbol: "arrow.uturn.backward", title: "撤销上一笔", shortcut: "⌘Z",
                                            action: #selector(undo)))
        stack.addArrangedSubview(makeSeparator())
        stack.addArrangedSubview(makeButton(symbol: "pin.fill", title: "固定贴图到屏幕", shortcut: nil,
                                            action: #selector(pin)))
        stack.addArrangedSubview(makeButton(symbol: "square.and.arrow.down", title: "保存截图到文件", shortcut: "⌘S",
                                            action: #selector(save)))
        stack.addArrangedSubview(makeButton(symbol: "doc.on.doc", title: "复制并完成", shortcut: "双击",
                                            action: #selector(copyImage)))
        stack.addArrangedSubview(makeButton(symbol: "xmark", title: "取消退出", shortcut: "Esc",
                                            action: #selector(close)))
        let confirmButton = makeButton(symbol: "checkmark", title: "完成截图并复制", shortcut: "↩",
                                       action: #selector(copyImage))
        confirmButton.contentTintColor = ScreenshotDesignTokens.iconPrimary
        stack.addArrangedSubview(confirmButton)

        setSelectedTool(.rectangle)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            hideTooltip()
        }
    }

    func setSelectedTool(_ tool: AnnotationTool) {
        currentSelectedTool = tool
        for (candidate, button) in toolButtons {
            button.isToolSelected = (candidate == tool)
        }
        // 关键改动：马赛克无色彩属性，自动弱化禁用色板按钮以避免用户误解
        colorButton.alphaValue = (tool == .mosaic) ? 0.3 : 1.0
        colorButton.isEnabled = (tool != .mosaic)
        if tool == .mosaic {
            widthButton.popoverTitle = "马赛克模糊度调节"
        } else if tool == .text {
            widthButton.popoverTitle = "文字字号调节"
        } else {
            widthButton.popoverTitle = "画笔粗细调节"
        }
    }

    func button(for tool: AnnotationTool) -> NSView? {
        return toolButtons[tool]
    }

    func setColor(_ color: NSColor) {
        colorButton.swatchColor = color
    }

    func setWidth(_ width: CGFloat) {
        widthButton.buttonCustomText = String(Int(round(width)))
    }

    private func makeButton(symbol: String, title: String, shortcut: String?, action: Selector) -> ScreenshotToolbarButton {
        let button = ScreenshotToolbarButton()
        configure(button, symbol: symbol, title: title, shortcut: shortcut, action: action)
        return button
    }

    private func configure(_ button: ScreenshotToolbarButton, symbol: String?, title: String, shortcut: String?, action: Selector) {
        button.isBordered = false
        button.focusRingType = .none // 关键改动：禁用系统原生焦点圈，防止产生不规则不对称轮廓
        button.target = self
        button.action = action
        button.popoverTitle = title
        button.popoverShortcut = shortcut
        button.setAccessibilityLabel(title)
        button.wantsLayer = true
        button.translatesAutoresizingMaskIntoConstraints = false

        // 关键改动：锁死 30x30 绝对正方形
        let widthConstraint = button.widthAnchor.constraint(equalToConstant: 30)
        let heightConstraint = button.heightAnchor.constraint(equalToConstant: 30)
        widthConstraint.priority = .required
        heightConstraint.priority = .required
        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint
        ])
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .vertical)

        if let symbol {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
            button.imagePosition = .imageOnly
        }

        button.onHoverChanged = { [weak self, weak button] isHovered in
            guard let self, let button else { return }
            if isHovered {
                self.showTooltip(for: button)
            } else {
                self.hideTooltip()
            }
        }
    }

    private func makeSeparator() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.widthAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 16)
        ])
        return line
    }

    // MARK: - 悬浮气泡 Popover Tooltip 展示与自适应宽度定位

    fileprivate func showTooltip(for button: ScreenshotToolbarButton) {
        guard let canvas = superview else { return }
        let title = button.popoverTitle
        let shortcut = button.popoverShortcut

        let tooltip: ScreenshotTooltipView
        if let existing = activeTooltip {
            tooltip = existing
            tooltip.update(title: title, shortcut: shortcut)
        } else {
            tooltip = ScreenshotTooltipView(title: title, shortcut: shortcut)
            canvas.addSubview(tooltip)
            activeTooltip = tooltip
        }

        let buttonRect = button.convert(button.bounds, to: canvas)
        tooltip.layoutSubtreeIfNeeded()
        // 关键改动：移除固定下限与硬编码外边距，依据内容精准自适应宽度，消除右侧留白
        let tooltipFitting = tooltip.fittingSize
        let tipWidth = ceil(tooltipFitting.width)
        let tipHeight = max(24, ceil(tooltipFitting.height))
        var tipX = buttonRect.midX - tipWidth / 2
        tipX = min(canvas.bounds.maxX - tipWidth - 8, max(8, tipX))
        var tipY = buttonRect.maxY + 7
        if tipY + tipHeight > canvas.bounds.maxY - 8 {
            tipY = buttonRect.minY - tipHeight - 7
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            tooltip.frame = NSRect(x: tipX, y: tipY, width: tipWidth, height: tipHeight)
            tooltip.alphaValue = 1.0
        }
    }

    fileprivate func hideTooltip() {
        guard let tooltip = activeTooltip else { return }
        activeTooltip = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.08
            tooltip.alphaValue = 0.0
        }, completionHandler: {
            tooltip.removeFromSuperview()
        })
    }

    @objc private func selectTool(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let tool = AnnotationTool(rawValue: raw) else { return }
        let isToggle = (currentSelectedTool == tool)
        setSelectedTool(tool)
        // 关键改动：向代理传递当前是否重复点击激活状态与当前按钮锚点，以便直接弹出关联调节条
        delegate?.toolbar(self, selected: tool, isToggle: isToggle, anchorView: sender)
    }

    @objc private func openColorPicker() {
        hideTooltip()
        delegate?.toolbarDidRequestColorPicker(self, anchorView: colorButton)
    }

    @objc private func openSizeSlider() {
        hideTooltip()
        let anchor = (currentSelectedTool == .mosaic ? (toolButtons[.mosaic] ?? widthButton) : widthButton)
        delegate?.toolbarDidRequestSizeSlider(self, anchorView: anchor)
    }

    @objc private func undo() { delegate?.toolbarDidUndo(self) }
    @objc private func pin() { delegate?.toolbarDidPin(self) }
    @objc private func save() { delegate?.toolbarDidSave(self) }
    @objc private func copyImage() { delegate?.toolbarDidCopy(self) }
    @objc private func close() { delegate?.toolbarDidClose(self) }
}

/// 截图底部工具栏悬浮高精度 Popover 提示胶囊：自动紧凑贴合文本与快捷键徽标
final class ScreenshotTooltipView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let shortcutBadge = NSTextField(labelWithString: "")

    init(title: String, shortcut: String?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 0.8
        layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        layer?.backgroundColor = NSColor(red: 22.0 / 255.0, green: 25.0 / 255.0, blue: 32.0 / 255.0, alpha: 0.96).cgColor
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow?.shadowBlurRadius = 8
        shadow?.shadowOffset = NSSize(width: 0, height: -2)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 5
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        titleLabel.font = .systemFont(ofSize: 11, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.addArrangedSubview(titleLabel)

        shortcutBadge.font = .monospacedSystemFont(ofSize: 9.5, weight: .semibold)
        shortcutBadge.textColor = NSColor.white.withAlphaComponent(0.9)
        shortcutBadge.wantsLayer = true
        shortcutBadge.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        shortcutBadge.layer?.cornerRadius = 3
        shortcutBadge.layer?.borderWidth = 0.5
        shortcutBadge.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        shortcutBadge.setContentHuggingPriority(.required, for: .horizontal)
        shortcutBadge.setContentCompressionResistancePriority(.required, for: .horizontal)
        stack.addArrangedSubview(shortcutBadge)

        update(title: title, shortcut: shortcut)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(title: String, shortcut: String?) {
        titleLabel.stringValue = title
        if let shortcut, !shortcut.isEmpty {
            shortcutBadge.stringValue = " \(shortcut) "
            shortcutBadge.isHidden = false
        } else {
            shortcutBadge.isHidden = true
        }
        layoutSubtreeIfNeeded()
        invalidateIntrinsicContentSize()
    }
}

/// 统一绘制规范的工具栏按钮：严格 28x28 内嵌圆角矩形，边框与外边距 100% 绝对一致
private final class ScreenshotToolbarButton: NSButton {
    var popoverTitle: String = ""
    var popoverShortcut: String?
    var onHoverChanged: ((Bool) -> Void)?

    var isColorSwatchButton: Bool = false
    var swatchColor: NSColor = .systemRed {
        didSet {
            if isColorSwatchButton {
                needsDisplay = true
            }
        }
    }

    var buttonCustomText: String? {
        didSet {
            needsDisplay = true
        }
    }

    private var trackingAreaRef: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    var isToolSelected = false {
        didSet { updateAppearance() }
    }

    override var alignmentRectInsets: NSEdgeInsets {
        return NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 30, height: 30)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        focusRingType = .none
        isBordered = false
        contentTintColor = NSColor(white: 0.88, alpha: 1.0)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateAppearance()
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        isPressed = false
        updateAppearance()
        onHoverChanged?(false)
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateAppearance()
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        updateAppearance()
        super.mouseUp(with: event)
    }

    private func updateAppearance() {
        if isToolSelected {
            contentTintColor = ScreenshotDesignTokens.iconPrimary
        } else if isPressed || isHovered {
            contentTintColor = .white
        } else {
            contentTintColor = NSColor(white: 0.88, alpha: 1.0)
        }
        needsDisplay = true
    }

    // 关键改动：所有按钮统一度量绘制 28x28（内缩 1pt）圆角边框，消除因 Cell 内部度量差异导致的参差不齐
    override func draw(_ dirtyRect: NSRect) {
        let box = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)

        if isToolSelected {
            let bgColor = ScreenshotDesignTokens.iconPrimary.withAlphaComponent(isHovered ? 0.30 : 0.22)
            bgColor.setFill()
            path.fill()
            ScreenshotDesignTokens.iconPrimary.setStroke()
            path.lineWidth = 1.0
            path.stroke()
        } else if isPressed {
            let bgColor = NSColor.white.withAlphaComponent(0.24)
            bgColor.setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.35).setStroke()
            path.lineWidth = 1.0
            path.stroke()
        } else if isHovered {
            let bgColor = NSColor.white.withAlphaComponent(0.16)
            bgColor.setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.28).setStroke()
            path.lineWidth = 1.0
            path.stroke()
        }

        if isColorSwatchButton {
            // 绘制独立色板圆点，居中并带精细保护描边
            let swatchRect = NSRect(x: bounds.midX - 6.5, y: bounds.midY - 6.5, width: 13, height: 13)
            let circle = NSBezierPath(ovalIn: swatchRect)
            swatchColor.setFill()
            circle.fill()
            NSColor.white.withAlphaComponent(0.4).setStroke()
            circle.lineWidth = 0.8
            circle.stroke()
        } else if let customText = buttonCustomText {
            // 绘制数值文本：严格几何居中，无任何 baseline 漂移
            let textFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold)
            let textColor = isToolSelected ? ScreenshotDesignTokens.iconPrimary : (isHovered ? .white : NSColor(white: 0.88, alpha: 1.0))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: textFont,
                .foregroundColor: textColor
            ]
            let str = customText as NSString
            let strSize = str.size(withAttributes: attrs)
            let textRect = NSRect(
                x: bounds.midX - strSize.width / 2,
                y: bounds.midY - strSize.height / 2 - 0.5,
                width: strSize.width,
                height: strSize.height
            )
            str.draw(in: textRect, withAttributes: attrs)
        } else {
            super.draw(dirtyRect)
        }
    }
}

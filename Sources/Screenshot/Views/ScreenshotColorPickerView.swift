import AppKit

protocol ScreenshotColorPickerDelegate: AnyObject {
    func colorPicker(_ picker: ScreenshotColorPickerView, didSelectColor color: NSColor)
    func colorPickerDidRequestDismiss(_ picker: ScreenshotColorPickerView)
}

final class ScreenshotColorPickerView: NSVisualEffectView {
    weak var delegate: ScreenshotColorPickerDelegate?

    static let presets: [NSColor] = [
        .systemRed,
        .systemOrange,
        .systemYellow,
        .systemGreen,
        .systemTeal,
        .systemBlue,
        .systemPurple,
        .systemPink,
        .white,
        NSColor(white: 0.65, alpha: 1.0),
        .black,
        ScreenshotDesignTokens.iconPrimary // 集成系统配置高亮色 #43E9C9
    ]

    private var currentColor: NSColor
    private var swatchButtons: [ColorSwatchButton] = []

    init(selectedColor: NSColor) {
        self.currentColor = selectedColor
        super.init(frame: NSRect(x: 0, y: 0, width: 176, height: 86))
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 0.8
        layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor
        layer?.backgroundColor = NSColor(red: 20.0 / 255.0, green: 23.0 / 255.0, blue: 30.0 / 255.0, alpha: 0.96).cgColor
        shadow = NSShadow()
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow?.shadowBlurRadius = 14
        shadow?.shadowOffset = NSSize(width: 0, height: -3)

        setupLayout()

        // 监听系统颜色面板变化通知，保证调色板实时双向同步
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(colorPanelNotification(_:)),
            name: NSColorPanel.colorDidChangeNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func updateSelectedColor(_ color: NSColor) {
        self.currentColor = color
        for button in swatchButtons {
            button.isSelected = button.color.isEqualOrClose(to: color)
        }
    }

    private func setupLayout() {
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 6
        mainStack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // 预设色板两行网格 (每行 6 个)
        let row1 = NSStackView()
        row1.orientation = .horizontal
        row1.spacing = 6
        for color in Self.presets.prefix(6) {
            let button = makeSwatch(for: color)
            swatchButtons.append(button)
            row1.addArrangedSubview(button)
        }
        mainStack.addArrangedSubview(row1)

        let row2 = NSStackView()
        row2.orientation = .horizontal
        row2.spacing = 6
        for color in Self.presets.suffix(6) {
            let button = makeSwatch(for: color)
            swatchButtons.append(button)
            row2.addArrangedSubview(button)
        }
        mainStack.addArrangedSubview(row2)

        // 分割线
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.widthAnchor.constraint(equalToConstant: 160).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        mainStack.addArrangedSubview(separator)

        // 采色器动作条：屏幕吸管采样与系统调色板
        let actionStack = NSStackView()
        actionStack.orientation = .horizontal
        actionStack.spacing = 8
        actionStack.alignment = .centerY

        let samplerButton = makeActionButton(symbol: "eyedropper.halffull", title: "吸管取色",
                                             action: #selector(triggerSampler))
        let panelButton = makeActionButton(symbol: "paintpalette.fill", title: "调色板…",
                                           action: #selector(openColorPanel))

        actionStack.addArrangedSubview(samplerButton)
        actionStack.addArrangedSubview(panelButton)
        mainStack.addArrangedSubview(actionStack)
    }

    private func makeSwatch(for color: NSColor) -> ColorSwatchButton {
        let button = ColorSwatchButton(color: color)
        button.isSelected = color.isEqualOrClose(to: currentColor)
        button.target = self
        button.action = #selector(swatchClicked(_:))
        return button
    }

    private func makeActionButton(symbol: String, title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        button.isBordered = false
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = .white.withAlphaComponent(0.88)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.wantsLayer = true
        button.layer?.cornerRadius = 4
        button.toolTip = title
        return button
    }

    @objc private func swatchClicked(_ sender: ColorSwatchButton) {
        updateSelectedColor(sender.color)
        delegate?.colorPicker(self, didSelectColor: sender.color)
    }

    @objc private func triggerSampler() {
        NSColorSampler().show { [weak self] (sampledColor: NSColor?) in
            guard let self, let sampledColor else { return }
            DispatchQueue.main.async {
                self.updateSelectedColor(sampledColor)
                self.delegate?.colorPicker(self, didSelectColor: sampledColor)
            }
        }
    }

    @objc private func openColorPanel() {
        let panel = NSColorPanel.shared
        panel.color = currentColor
        panel.setTarget(self)
        // 关键：AppKit 标准选色器响应 Selector 必须为 changeColor:
        panel.setAction(#selector(changeColor(_:)))
        panel.isContinuous = true
        panel.level = .screenSaver + 1
        panel.orderFront(nil)
    }

    /// AppKit NSColorPanel 选色变化标准入口响应
    @objc func changeColor(_ sender: Any?) {
        let color = NSColorPanel.shared.color
        updateSelectedColor(color)
        delegate?.colorPicker(self, didSelectColor: color)
    }

    @objc private func colorPanelNotification(_ notification: Notification) {
        guard let panel = notification.object as? NSColorPanel else { return }
        updateSelectedColor(panel.color)
        delegate?.colorPicker(self, didSelectColor: panel.color)
    }
}

private final class ColorSwatchButton: NSButton {
    let color: NSColor
    var isSelected: Bool = false {
        didSet { needsDisplay = true }
    }

    init(color: NSColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 18),
            heightAnchor.constraint(equalToConstant: 18)
        ])
        isBordered = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func draw(_ dirtyRect: NSRect) {
        let circleRect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let path = NSBezierPath(ovalIn: circleRect)
        color.setFill()
        path.fill()

        NSColor.white.withAlphaComponent(0.3).setStroke()
        path.lineWidth = 1
        path.stroke()

        if isSelected {
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5))
            ScreenshotDesignTokens.iconPrimary.setStroke()
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

private extension NSColor {
    func isEqualOrClose(to other: NSColor) -> Bool {
        guard let c1 = self.usingColorSpace(.sRGB),
              let c2 = other.usingColorSpace(.sRGB) else { return self == other }
        return abs(c1.redComponent - c2.redComponent) < 0.05 &&
               abs(c1.greenComponent - c2.greenComponent) < 0.05 &&
               abs(c1.blueComponent - c2.blueComponent) < 0.05
    }
}

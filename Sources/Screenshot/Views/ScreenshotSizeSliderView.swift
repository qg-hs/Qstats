import AppKit

protocol ScreenshotSizeSliderDelegate: AnyObject {
    func sizeSlider(_ sliderView: ScreenshotSizeSliderView, didChangeSize size: CGFloat)
    func sizeSliderDidRequestDismiss(_ sliderView: ScreenshotSizeSliderView)
}

/// 截图标注画笔粗细、字号与马赛克模糊度通用平滑滑动调节器
final class ScreenshotSizeSliderView: NSVisualEffectView {
    weak var delegate: ScreenshotSizeSliderDelegate?

    private var currentSize: CGFloat
    private let unit: String
    private let titleLabel = NSTextField(labelWithString: "粗细 / 字号")
    private let valueLabel = NSTextField(labelWithString: "4 px")
    private let slider = NSSlider()
    private let previewDot = NSView()
    private var presetButtons: [NSButton] = []

    init(currentSize: CGFloat,
         title: String = "粗细 / 字号",
         minValue: CGFloat = 1.0,
         maxValue: CGFloat = 32.0,
         presets: [CGFloat] = [2, 4, 8, 16],
         unit: String = "px") {
        self.currentSize = currentSize
        self.unit = unit
        super.init(frame: NSRect(x: 0, y: 0, width: 204, height: 88))
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
        shadow?.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow?.shadowBlurRadius = 14
        shadow?.shadowOffset = NSSize(width: 0, height: -3)

        titleLabel.stringValue = title
        setupLayout(minValue: minValue, maxValue: maxValue, presets: presets)
        updateDisplay(size: currentSize)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupLayout(minValue: CGFloat, maxValue: CGFloat, presets: [CGFloat]) {
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.spacing = 7
        mainStack.alignment = .leading
        mainStack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)
        NSLayoutConstraint.activate([
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: topAnchor),
            mainStack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        // 顶部标题与当前数值
        let topRow = NSStackView()
        topRow.orientation = .horizontal
        topRow.spacing = 6
        topRow.alignment = .centerY
        topRow.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = ScreenshotDesignTokens.iconPrimary
        topRow.addArrangedSubview(titleLabel)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        topRow.addArrangedSubview(spacer)

        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .white
        topRow.addArrangedSubview(valueLabel)

        // 动态预览圆点
        previewDot.wantsLayer = true
        previewDot.layer?.backgroundColor = ScreenshotDesignTokens.iconPrimary.cgColor
        previewDot.layer?.cornerRadius = 3
        previewDot.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            previewDot.widthAnchor.constraint(equalToConstant: 16),
            previewDot.heightAnchor.constraint(equalToConstant: 16)
        ])
        topRow.addArrangedSubview(previewDot)

        mainStack.addArrangedSubview(topRow)
        topRow.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -20).isActive = true

        // 中部平滑滑动条：依据传入的极值动态配置范围
        slider.minValue = Double(minValue)
        slider.maxValue = Double(maxValue)
        slider.doubleValue = Double(currentSize)
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(slider)
        slider.widthAnchor.constraint(equalTo: mainStack.widthAnchor, constant: -20).isActive = true

        // 底部快捷挡位芯片：依据传入预设数组动态构建
        let chipsRow = NSStackView()
        chipsRow.orientation = .horizontal
        chipsRow.spacing = 6
        chipsRow.alignment = .centerY

        for preset in presets {
            let chip = NSButton(title: "\(Int(preset))", target: self, action: #selector(chipClicked(_:)))
            chip.tag = Int(preset)
            chip.bezelStyle = .inline
            chip.isBordered = false
            chip.wantsLayer = true
            chip.layer?.cornerRadius = 4
            chip.layer?.borderWidth = 0.5
            chip.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
            chip.layer?.backgroundColor = ScreenshotDesignTokens.iconBgLight.cgColor
            chip.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            chip.contentTintColor = .white
            chip.translatesAutoresizingMaskIntoConstraints = false
            chip.widthAnchor.constraint(equalToConstant: 34).isActive = true
            chip.heightAnchor.constraint(equalToConstant: 18).isActive = true
            presetButtons.append(chip)
            chipsRow.addArrangedSubview(chip)
        }
        mainStack.addArrangedSubview(chipsRow)
    }

    func updateSize(_ size: CGFloat) {
        currentSize = size
        slider.doubleValue = Double(size)
        updateDisplay(size: size)
    }

    private func updateDisplay(size: CGFloat) {
        valueLabel.stringValue = "\(Int(round(size))) \(unit)"
        let dotSize = max(3.0, min(14.0, size))
        previewDot.layer?.cornerRadius = dotSize / 2.0
        previewDot.layer?.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)

        for btn in presetButtons {
            let isCurrent = btn.tag == Int(round(size))
            btn.layer?.borderColor = isCurrent
                ? ScreenshotDesignTokens.iconPrimary.cgColor
                : NSColor.white.withAlphaComponent(0.2).cgColor
            btn.contentTintColor = isCurrent ? ScreenshotDesignTokens.iconPrimary : .white
        }
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let size = CGFloat(sender.doubleValue)
        currentSize = size
        updateDisplay(size: size)
        delegate?.sizeSlider(self, didChangeSize: size)
    }

    @objc private func chipClicked(_ sender: NSButton) {
        let size = CGFloat(sender.tag)
        slider.doubleValue = Double(size)
        currentSize = size
        updateDisplay(size: size)
        delegate?.sizeSlider(self, didChangeSize: size)
    }
}

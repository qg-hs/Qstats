import AppKit

final class ShortcutRecorderView: NSView {
    private let keyLabel = NSTextField(labelWithString: "")
    private let hintLabel = NSTextField(labelWithString: "按下新的组合键")

    var shortcut: KeyboardShortcut? {
        didSet {
            keyLabel.stringValue = shortcut?.displayName ?? "等待输入"
            hintLabel.stringValue = shortcut == nil ? "需包含 ⌃、⌥、⇧ 或 ⌘" : "已录入，点击“保存”应用"
            hintLabel.textColor = shortcut == nil ? .secondaryLabelColor : .systemGreen
        }
    }

    init(shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 82))

        let keyBackground = NSVisualEffectView()
        keyBackground.material = .contentBackground
        keyBackground.blendingMode = .withinWindow
        keyBackground.state = .active
        keyBackground.wantsLayer = true
        keyBackground.layer?.cornerRadius = 10
        keyBackground.layer?.borderWidth = 1
        keyBackground.layer?.borderColor = NSColor.separatorColor.cgColor
        keyBackground.translatesAutoresizingMaskIntoConstraints = false

        keyLabel.stringValue = shortcut.displayName
        keyLabel.font = .monospacedSystemFont(ofSize: 22, weight: .semibold)
        keyLabel.alignment = .center
        keyLabel.translatesAutoresizingMaskIntoConstraints = false

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.alignment = .center
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(keyBackground)
        keyBackground.addSubview(keyLabel)
        addSubview(hintLabel)

        NSLayoutConstraint.activate([
            keyBackground.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            keyBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            keyBackground.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            keyBackground.heightAnchor.constraint(equalToConstant: 48),
            keyLabel.centerXAnchor.constraint(equalTo: keyBackground.centerXAnchor),
            keyLabel.centerYAnchor.constraint(equalTo: keyBackground.centerYAnchor),
            hintLabel.topAnchor.constraint(equalTo: keyBackground.bottomAnchor, constant: 8),
            hintLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    func rejectInput() {
        shortcut = nil
        NSSound.beep()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

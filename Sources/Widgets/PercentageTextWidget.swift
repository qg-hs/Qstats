import AppKit

/// Stable width, including the unavailable GPU state, so selection never loses its menu.
struct PercentageTextWidget: StatusBarWidget {
    let icon: NSImage?
    let percentage: Double
    private let iconSize: CGFloat = 11
    private let gap: CGFloat = 4

    private var text: TextWidget {
        TextWidget(percentage < 0 ? "—" : String(format: "%.0f%%", min(100, max(0, percentage))),
                   sizedFor: "100%", font: .monospacedDigitSystemFont(ofSize: 10, weight: .medium))
    }

    func widthForHeight(_ height: CGFloat) -> CGFloat {
        (icon == nil ? 0 : iconSize + gap) + text.widthForHeight(height)
    }

    func draw(at origin: NSPoint, height: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        var x = origin.x
        if let icon {
            drawTemplateIcon(icon, in: NSRect(x: x, y: origin.y + (height - iconSize) / 2,
                                             width: iconSize, height: iconSize), ctx: ctx)
            x += iconSize + gap
        }
        text.draw(at: NSPoint(x: x, y: origin.y), height: height)
    }
}

import AppKit

struct VerticalBarWidget: StatusBarWidget {
    let icon: NSImage?
    let percentage: Double
    let tintColor: NSColor
    private let barWidth: CGFloat = 8
    private let iconSize: CGFloat = 11
    private let gap: CGFloat = 4
    private let cornerRadius: CGFloat = 2

    func widthForHeight(_ height: CGFloat) -> CGFloat {
        (icon != nil ? iconSize + gap : 0) + barWidth
    }

    func draw(at origin: NSPoint, height: CGFloat) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        var x = origin.x

        if let icon {
            drawTemplateIcon(icon, in: NSRect(x: x, y: origin.y + (height - iconSize) / 2,
                                              width: iconSize, height: iconSize), ctx: ctx)
            x += iconSize + gap
        }

        let barRect = CGRect(x: x, y: origin.y + (height - 16) / 2, width: barWidth, height: 16)

        // Track
        let trackPath = CGPath(roundedRect: barRect, cornerWidth: cornerRadius,
                               cornerHeight: cornerRadius, transform: nil)
        ctx.addPath(trackPath)
        ctx.setFillColor(NSColor.labelColor.withAlphaComponent(0.14).cgColor)
        ctx.fillPath()

        // Fill from bottom
        let fillHeight = barRect.height * CGFloat(min(100, max(0, percentage)) / 100.0)
        if fillHeight > 0 {
            let fillRect = CGRect(x: barRect.minX, y: barRect.minY,
                                  width: barRect.width, height: fillHeight)
            // Clip to rounded track, then fill
            ctx.saveGState()
            ctx.addPath(trackPath)
            ctx.clip()
            ctx.setFillColor(tintColor.cgColor)
            ctx.fill(fillRect)
            ctx.restoreGState()
        }
    }
}

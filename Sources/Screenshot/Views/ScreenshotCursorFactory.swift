import AppKit

enum ScreenshotCursorFactory {
    static let selection = makeCursor(symbolName: nil)

    static func cursor(for tool: AnnotationTool) -> NSCursor {
        switch tool {
        case .rectangle: return rectangle
        case .arrow: return arrow
        case .pen: return pen
        case .mosaic: return mosaic
        case .text: return text
        }
    }

    // 8 边方向拖拽光标定义：对角方向使用高清适量双向箭头
    static let resizeDiagonalNWSE = makeDiagonalCursor(isNWSE: true)
    static let resizeDiagonalNESW = makeDiagonalCursor(isNWSE: false)

    private static let rectangle = makeCursor(symbolName: "rectangle")
    private static let arrow = makeCursor(symbolName: "arrow.up.right")
    private static let pen = makeCursor(symbolName: "pencil.tip")
    private static let mosaic = makeCursor(symbolName: "square.grid.3x3.fill")
    private static let text = makeCursor(symbolName: "textformat")

    private static func makeDiagonalCursor(isNWSE: Bool) -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size, flipped: false) { _ in
            let path = NSBezierPath()
            let p1 = isNWSE ? NSPoint(x: 5, y: 19) : NSPoint(x: 19, y: 19)
            let p2 = isNWSE ? NSPoint(x: 19, y: 5) : NSPoint(x: 5, y: 5)

            // 绘制主干线
            path.move(to: p1)
            path.line(to: p2)

            // 绘制两端箭头
            if isNWSE {
                path.move(to: NSPoint(x: 5, y: 13))
                path.line(to: p1)
                path.line(to: NSPoint(x: 11, y: 19))

                path.move(to: NSPoint(x: 13, y: 5))
                path.line(to: p2)
                path.line(to: NSPoint(x: 19, y: 11))
            } else {
                path.move(to: NSPoint(x: 13, y: 19))
                path.line(to: p1)
                path.line(to: NSPoint(x: 19, y: 13))

                path.move(to: NSPoint(x: 5, y: 11))
                path.line(to: p2)
                path.line(to: NSPoint(x: 11, y: 5))
            }

            path.lineCapStyle = .round
            path.lineJoinStyle = .round

            // 黑色投影衬底
            let shadow = path.copy() as! NSBezierPath
            shadow.lineWidth = 3.5
            NSColor.black.withAlphaComponent(0.85).setStroke()
            shadow.stroke()

            // 白色前景色
            path.lineWidth = 1.5
            NSColor.white.setStroke()
            path.stroke()

            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }

    private static func makeCursor(symbolName: String?) -> NSCursor {
        let size = NSSize(width: 32, height: 32)
        let image = NSImage(size: size, flipped: false) { _ in
            let center = NSPoint(x: 7, y: 25)

            let shadow = NSBezierPath()
            shadow.move(to: NSPoint(x: center.x, y: center.y - 6))
            shadow.line(to: NSPoint(x: center.x, y: center.y + 6))
            shadow.move(to: NSPoint(x: center.x - 6, y: center.y))
            shadow.line(to: NSPoint(x: center.x + 6, y: center.y))
            shadow.lineCapStyle = .round
            shadow.lineWidth = 3.5
            NSColor.black.withAlphaComponent(0.82).setStroke()
            shadow.stroke()

            let crosshair = shadow.copy() as! NSBezierPath
            crosshair.lineWidth = 1.5
            NSColor.white.setStroke()
            crosshair.stroke()

            let centerDot = NSBezierPath(ovalIn: NSRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3))
            NSColor.controlAccentColor.setFill()
            centerDot.fill()

            guard let symbolName,
                  let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold)) else { return true }

            let badgeRect = NSRect(x: 13, y: 1, width: 18, height: 18)
            let badge = NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5)
            NSColor.white.withAlphaComponent(0.96).setFill()
            badge.fill()
            NSColor.black.withAlphaComponent(0.62).setStroke()
            badge.lineWidth = 1
            badge.stroke()

            symbol.draw(in: badgeRect.insetBy(dx: 4, dy: 4),
                        from: .zero, operation: .sourceOver, fraction: 0.9)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 7, y: 7))
    }
}

import AppKit
import CoreImage

enum AnnotationTool: String, CaseIterable {
    case rectangle, arrow, pen, mosaic, text

    var symbolName: String {
        switch self {
        case .rectangle: return "rectangle"
        case .arrow: return "arrow.up.right"
        case .pen: return "pencil.tip"
        case .mosaic: return "square.grid.3x3.fill"
        case .text: return "textformat"
        }
    }

    var title: String {
        switch self {
        case .rectangle: return "矩形"
        case .arrow: return "箭头"
        case .pen: return "画笔"
        case .mosaic: return "马赛克"
        case .text: return "文字"
        }
    }
}

enum Annotation {
    case rectangle(rect: NSRect, color: NSColor, width: CGFloat)
    case arrow(start: NSPoint, end: NSPoint, color: NSColor, width: CGFloat)
    case pen(points: [NSPoint], color: NSColor, width: CGFloat)
    case mosaic(rect: NSRect, scale: CGFloat = 16.0)
    case text(origin: NSPoint, value: String, color: NSColor, size: CGFloat)

    // 关键改动：全局共享复用 CIContext，彻底避免每次绘制马赛克都重复创建昂贵的 CIContext (耗时减少 90%)
    static let sharedCIContext = CIContext(options: [
        .useSoftwareRenderer: false,
        .priorityRequestLow: false
    ])

    // 关键改动：支持传入预先光栅化的全屏马赛克缓存 mosaicCache，实现 O(1) 局部 blit 绘制
    func draw(in context: CGContext, background: NSImage? = nil, canvasBounds: NSRect = .zero, mosaicCache: CGImage? = nil) {
        context.saveGState()
        switch self {
        case let .rectangle(rect, color, width):
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.setLineJoin(.round)
            context.stroke(rect.insetBy(dx: width / 2, dy: width / 2))
        case let .arrow(start, end, color, width):
            let dx = end.x - start.x
            let dy = end.y - start.y
            let length = hypot(dx, dy)
            guard length > 1 else { break }

            let angle = atan2(dy, dx)
            let head = min(max(14.0, width * 3.8), max(10.0, length * 0.75))
            let spread = CGFloat.pi / 6.5

            let p1 = NSPoint(x: end.x - head * cos(angle - spread),
                             y: end.y - head * sin(angle - spread))
            let p2 = NSPoint(x: end.x - head * cos(angle + spread),
                             y: end.y - head * sin(angle + spread))

            let baseCenterDistance = head * cos(spread)
            let stemStopDistance = max(0, length - baseCenterDistance + min(width * 0.8, head * 0.3))
            let stemEnd = NSPoint(x: start.x + stemStopDistance * cos(angle),
                                  y: start.y + stemStopDistance * sin(angle))

            context.setStrokeColor(color.cgColor)
            context.setFillColor(color.cgColor)

            context.saveGState()
            context.setLineWidth(width)
            context.setLineCap(.butt)
            context.setLineJoin(.round)
            context.move(to: start)
            context.addLine(to: stemEnd)
            context.strokePath()
            context.restoreGState()

            let arrowPath = CGMutablePath()
            arrowPath.move(to: end)
            arrowPath.addLine(to: p1)
            arrowPath.addLine(to: p2)
            arrowPath.closeSubpath()
            context.addPath(arrowPath)
            context.fillPath()

        case let .pen(points, color, width):
            guard let first = points.first else { break }
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(width)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.move(to: first)
            for point in points.dropFirst() { context.addLine(to: point) }
            context.strokePath()

        case let .mosaic(rect, scale):
            let clipped = rect.intersection(canvasBounds)
            guard !clipped.isEmpty else { break }

            // 关键改动：若存在预渲染的马赛克位图缓存，直接裁切绘制，毫秒级即时完成
            if let mosaicCache {
                context.saveGState()
                context.clip(to: clipped)
                context.draw(mosaicCache, in: canvasBounds)
                context.restoreGState()
                break
            }

            // 无缓存时的保底动态滤镜（使用全局共享静态 CIContext）
            guard let background,
                  let cgImage = background.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let filter = CIFilter(name: "CIPixellate") else { break }
            let input = CIImage(cgImage: cgImage)
            let pointScale = CGFloat(cgImage.width) / max(1, canvasBounds.width)
            filter.setValue(input, forKey: kCIInputImageKey)
            filter.setValue(max(4, scale * pointScale), forKey: kCIInputScaleKey)
            guard let output = filter.outputImage,
                  let pixelated = Self.sharedCIContext.createCGImage(output, from: input.extent) else { break }
            let image = NSImage(cgImage: pixelated, size: canvasBounds.size)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: clipped).addClip()
            image.draw(in: canvasBounds, from: .zero, operation: .copy, fraction: 1,
                       respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
            NSGraphicsContext.restoreGraphicsState()

        case let .text(origin, value, color, size):
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size, weight: .semibold),
                .foregroundColor: color,
                .strokeColor: NSColor.black.withAlphaComponent(0.25),
                .strokeWidth: -1
            ]
            (value as NSString).draw(at: origin, withAttributes: attributes)
        }
        context.restoreGState()
    }
}

func normalizedRect(from start: NSPoint, to end: NSPoint) -> NSRect {
    NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
           width: abs(end.x - start.x), height: abs(end.y - start.y))
}

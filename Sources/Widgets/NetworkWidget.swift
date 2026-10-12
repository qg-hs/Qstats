import AppKit

/// Two-row stacked network widget: download on top, upload on bottom.
/// Fixed width sized for max expected value to prevent shifting.
struct NetworkWidget: StatusBarWidget {
    let downText: String
    let upText: String
    let downBytes: UInt64
    let upBytes: UInt64

    private let font = NSFont.monospacedSystemFont(ofSize: 8, weight: .medium)
    private let arrowFont = NSFont.monospacedSystemFont(ofSize: 8, weight: .semibold)
    private let dotGap: CGFloat = 1.0 // 关键优化：紧凑间距，箭头与数值不再被大间隙撕裂
    private let rowGap: CGFloat = 0
    private let contentWidth: CGFloat

    init(down: String, up: String, downBytes: UInt64 = 0, upBytes: UInt64 = 0) {
        self.downText = down
        self.upText = up
        // 优先使用传入的原始字节率；若未传入则解析格式化字符串作为兜底
        self.downBytes = downBytes != 0 ? downBytes : Self.parseBytes(from: down)
        self.upBytes = upBytes != 0 ? upBytes : Self.parseBytes(from: up)

        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let arrowAttrsInit: [NSAttributedString.Key: Any] = [.font: arrowFont]
        let downArrowWidth = ceil(("↓" as NSString).size(withAttributes: arrowAttrsInit).width)
        let upArrowWidth = ceil(("↑" as NSString).size(withAttributes: arrowAttrsInit).width)
        let arrowWidth = max(downArrowWidth, upArrowWidth)

        // 关键改动：宽度精准自适应当前文本内容，保证状态栏胶囊内左右 padding 严格对称，彻底消除右侧多余空白
        let downTextWidth = ceil((down as NSString).size(withAttributes: attrs).width)
        let upTextWidth = ceil((up as NSString).size(withAttributes: attrs).width)
        let maxTextWidth = max(downTextWidth, upTextWidth)
        self.contentWidth = arrowWidth + dotGap + maxTextWidth
    }

    func widthForHeight(_ height: CGFloat) -> CGFloat { contentWidth }

    // MARK: - 下载色谱体系（冷萃科技系：天蓝 -> 科技蓝 -> 极速青绿）

    // 关键改动：独立下载专属色系，彻底拉开与上传的色相距离，避免视觉混淆
    static func downloadColor(forBytesPerSec bytes: UInt64) -> NSColor {
        let kb = Double(bytes) / 1024.0
        if kb < 100.0 {
            // < 100k：下载慢速/低频 -> 晴空天蓝 (#38BDF8 / #0284C7)
            return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 56 / 255.0, green: 189 / 255.0, blue: 248 / 255.0, alpha: 1.0)
                    : NSColor(red: 2 / 255.0, green: 132 / 255.0, blue: 199 / 255.0, alpha: 1.0)
            }
        } else if kb <= 500.0 {
            // 100k - 500k：下载中速平稳 -> 纯正科技蓝 (#60A5FA / #2563EB)
            return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 96 / 255.0, green: 165 / 255.0, blue: 250 / 255.0, alpha: 1.0)
                    : NSColor(red: 37 / 255.0, green: 99 / 255.0, blue: 235 / 255.0, alpha: 1.0)
            }
        } else {
            // > 500k：下载高速顺畅 -> 品牌极速青绿 (#43E9C9 / #059669)
            return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 67 / 255.0, green: 233 / 255.0, blue: 201 / 255.0, alpha: 1.0)
                    : NSColor(red: 5 / 255.0, green: 150 / 255.0, blue: 105 / 255.0, alpha: 1.0)
            }
        }
    }

    // MARK: - 上传色谱体系（暖阳热力系：暖黄 -> 活力橙 -> 高能洋红玫瑰）

    // 关键改动：独立上传专属色系，形成天然冷暖互补对比，一眼即可辨识方向
    static func uploadColor(forBytesPerSec bytes: UInt64) -> NSColor {
        let kb = Double(bytes) / 1024.0
        if kb < 100.0 {
            // < 100k：上传慢速/低频 -> 暖阳琥珀黄 (#FBBF24 / #D97706)
            return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 251 / 255.0, green: 191 / 255.0, blue: 36 / 255.0, alpha: 1.0)
                    : NSColor(red: 217 / 255.0, green: 119 / 255.0, blue: 6 / 255.0, alpha: 1.0)
            }
        } else if kb <= 500.0 {
            // 100k - 500k：上传中速平稳 -> 活力鲜橙色 (#FB923C / #EA580C)
            return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 251 / 255.0, green: 146 / 255.0, blue: 60 / 255.0, alpha: 1.0)
                    : NSColor(red: 234 / 255.0, green: 88 / 255.0, blue: 12 / 255.0, alpha: 1.0)
            }
        } else {
            // > 500k：上传高速顺畅 -> 高能霓虹玫瑰粉 (#F43F5E / #E11D48)
            return NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(red: 244 / 255.0, green: 63 / 255.0, blue: 94 / 255.0, alpha: 1.0)
                    : NSColor(red: 225 / 255.0, green: 29 / 255.0, blue: 72 / 255.0, alpha: 1.0)
            }
        }
    }

    /// 向后兼容：默认映射到下载色彩梯度
    static func color(forBytesPerSec bytes: UInt64) -> NSColor {
        downloadColor(forBytesPerSec: bytes)
    }

    private static func parseBytes(from text: String) -> UInt64 {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: " ")
        guard let numStr = parts.first, let val = Double(numStr) else { return 0 }
        if trimmed.contains("GB") { return UInt64(val * 1024 * 1024 * 1024) }
        if trimmed.contains("MB") { return UInt64(val * 1024 * 1024) }
        if trimmed.contains("KB") { return UInt64(val * 1024) }
        return UInt64(val)
    }

    func draw(at origin: NSPoint, height: CGFloat) {
        guard NSGraphicsContext.current?.cgContext != nil else { return }

        let sampleAttrs: [NSAttributedString.Key: Any] = [.font: font]
        let textHeight = ceil(("X" as NSString).size(withAttributes: sampleAttrs).height)
        let totalHeight = textHeight * 2 + rowGap
        let topY = origin.y + (height + totalHeight) / 2 - textHeight   // top row baseline
        let botY = topY - textHeight - rowGap                             // bottom row baseline

        let downArrowWidth = ceil(("↓" as NSString).size(withAttributes: [.font: arrowFont]).width)
        let upArrowWidth = ceil(("↑" as NSString).size(withAttributes: [.font: arrowFont]).width)
        let arrowWidth = max(downArrowWidth, upArrowWidth)
        let textX = origin.x + arrowWidth + dotGap

        // 关键改动：Down row 使用独立的冷翠色谱体系（天蓝 -> 科技蓝 -> 极速青绿）
        let downColor = Self.downloadColor(forBytesPerSec: downBytes)
        let downArrowAttrs: [NSAttributedString.Key: Any] = [
            .font: arrowFont,
            .foregroundColor: downColor,
        ]
        let downAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: downColor,
        ]
        ("↓" as NSString).draw(at: NSPoint(x: origin.x, y: topY), withAttributes: downArrowAttrs)
        // 关键改动：文字直接紧靠箭头右侧排版，彻底消除右对齐在小流量时拉出的巨大空当
        (downText as NSString).draw(at: NSPoint(x: textX, y: topY), withAttributes: downAttrs)

        // 关键改动：Up row 使用独立的暖阳色谱体系（暖黄 -> 活力橙 -> 高能玫瑰粉），与下载形成鲜明区分
        let upColor = Self.uploadColor(forBytesPerSec: upBytes)
        let upArrowAttrs: [NSAttributedString.Key: Any] = [
            .font: arrowFont,
            .foregroundColor: upColor,
        ]
        let upAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: upColor,
        ]
        ("↑" as NSString).draw(at: NSPoint(x: origin.x, y: botY), withAttributes: upArrowAttrs)
        // 关键改动：文字直接紧靠箭头右侧排版，紧凑稳健
        (upText as NSString).draw(at: NSPoint(x: textX, y: botY), withAttributes: upAttrs)
    }
}

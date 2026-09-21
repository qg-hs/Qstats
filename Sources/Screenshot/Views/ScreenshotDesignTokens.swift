import AppKit

/// 截图模块与标注工具栏统一设计系统 Token
/// 严格映射配置色：
/// --icon-bg: #0A1C3F
/// --icon-bg-light: #123450
/// --icon-primary: #43E9C9
/// --icon-primary-dark: #3BC2AE
/// --icon-primary-deep: #2C948F
enum ScreenshotDesignTokens {
    /// 核心背景底色深蓝 (#0A1C3F)
    static let iconBg = NSColor(red: 10.0 / 255.0, green: 28.0 / 255.0, blue: 63.0 / 255.0, alpha: 1.0)

    /// 辅助底色 / 悬浮高亮色 (#123450)
    static let iconBgLight = NSColor(red: 18.0 / 255.0, green: 52.0 / 255.0, blue: 80.0 / 255.0, alpha: 1.0)

    /// 主题青绿高亮色 (#43E9C9)
    static let iconPrimary = NSColor(red: 67.0 / 255.0, green: 233.0 / 255.0, blue: 201.0 / 255.0, alpha: 1.0)

    /// 主题次级青绿 (#3BC2AE)
    static let iconPrimaryDark = NSColor(red: 59.0 / 255.0, green: 194.0 / 255.0, blue: 174.0 / 255.0, alpha: 1.0)

    /// 主题深青绿 (#2C948F)
    static let iconPrimaryDeep = NSColor(red: 44.0 / 255.0, green: 148.0 / 255.0, blue: 143.0 / 255.0, alpha: 1.0)
}

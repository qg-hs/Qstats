import AppKit
import IOKit

/// 构建并实时更新状态栏下拉详情菜单（SF Symbol 图标、中文本地化、紧凑右对齐排版及流向着色）
final class StatsMenuBuilder {
    private var cpuItem: NSMenuItem?
    private var memoryItem: NSMenuItem?
    private var gpuItem: NSMenuItem?
    // 关键改动：将原本独立的上传与下载菜单项合并为单行展示容器
    private var networkItem: NSMenuItem?

    private let config: AppConfig
    private let cpuLabel: String   // 如 "CPU (10)"
    private let gpuLabel: String   // 如 "GPU (1)"

    init(config: AppConfig) {
        self.config = config

        let coreCount = ProcessInfo.processInfo.processorCount
        cpuLabel = "CPU (\(coreCount))"

        let gpuCount = StatsMenuBuilder.gpuCount()
        gpuLabel = gpuCount > 0 ? "GPU (\(gpuCount))" : "GPU"
    }

    func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        cpuItem = nil
        memoryItem = nil
        gpuItem = nil
        networkItem = nil

        // 监控项排布
        if config.showCPU {
            cpuItem = makeRow(icon: "cpu", label: cpuLabel, value: "—")
            menu.addItem(cpuItem!)
        }
        if config.showMemory {
            memoryItem = makeRow(icon: "memorychip", label: "内存", value: "—")
            menu.addItem(memoryItem!)
        }
        if config.showGPU {
            gpuItem = makeRow(icon: "display", label: gpuLabel, value: "—")
            menu.addItem(gpuItem!)
        }
        // 关键改动：上传、下载合并为单行显示，不占两行
        if config.showNetwork {
            if config.showCPU || config.showMemory || config.showGPU {
                menu.addItem(NSMenuItem.separator())
            }
            networkItem = makeNetworkRow()
            menu.addItem(networkItem!)
        }

        menu.addItem(NSMenuItem.separator())
    }

    func update(snapshot: StatsSnapshot) {
        let cpuVal = String(format: "%.1f%%", snapshot.cpu)
        updateItem(cpuItem, label: cpuLabel, value: cpuVal,
                   valueColor: snapshot.cpu >= 80 ? .systemOrange : .secondaryLabelColor)

        // 内存：紧凑格式，减少菜单宽度
        let memVal = String(format: "%.1f/%.1fG  %.0f%%",
                            snapshot.memory.usedGB, snapshot.memory.totalGB, snapshot.memory.percentage)
        updateItem(memoryItem, label: "内存", value: memVal,
                   valueColor: snapshot.memory.percentage >= 85 ? .systemOrange : .secondaryLabelColor)

        let gpuVal = snapshot.gpu >= 0 ? String(format: "%.1f%%", snapshot.gpu) : "不可用"
        updateItem(gpuItem, label: gpuLabel, value: gpuVal, valueColor: .secondaryLabelColor)

        // 关键改动：单行同时渲染下载与上传，实时同步专属冷暖色谱并保持定宽槽位防抖
        if let networkItem {
            let downColor = NetworkWidget.downloadColor(forBytesPerSec: snapshot.network.bytesInPerSec)
            let upColor = NetworkWidget.uploadColor(forBytesPerSec: snapshot.network.bytesOutPerSec)
            updateNetworkItem(networkItem,
                              downText: snapshot.network.formattedIn,
                              upText: snapshot.network.formattedOut,
                              downColor: downColor,
                              upColor: upColor)
        }
    }

    private func makeRow(icon symbolName: String, label: String, value: String) -> NSMenuItem {
        let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        item.isEnabled = true

        if let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: label) {
            let symConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            item.image = img.withSymbolConfiguration(symConfig)
        }

        updateItem(item, label: label, value: value)
        return item
    }

    // 关键改动：构建合并后的网络速率单行项，采用双向箭头图标，初始占位符即为定宽槽位
    private func makeNetworkRow() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.isEnabled = true

        if let img = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "网络速率") {
            let symConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            item.image = img.withSymbolConfiguration(symConfig)
        }

        updateNetworkItem(item, downText: "0 KB/s", upText: "0 KB/s", downColor: .secondaryLabelColor, upColor: .secondaryLabelColor)
        return item
    }

    /// 制表位收窄至 120pt，配合紧凑内存格式控制菜单整体宽度
    private func updateItem(_ item: NSMenuItem?, label: String, value: String, valueColor: NSColor = .secondaryLabelColor) {
        guard let item else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [
            NSTextTab(textAlignment: .right, location: 120, options: [:])
        ]

        let attrStr = NSMutableAttributedString()
        attrStr.append(NSAttributedString(
            string: "\(label)\t",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraph,
            ]
        ))
        attrStr.append(NSAttributedString(
            string: value,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: valueColor,
                .paragraphStyle: paragraph,
            ]
        ))
        item.attributedTitle = attrStr
    }

    // 关键改动：严格采用定宽槽位与等宽字体排版，杜绝因数值变化导致的菜单宽度抖动
    private func updateNetworkItem(_ item: NSMenuItem?, downText: String, upText: String, downColor: NSColor, upColor: NSColor) {
        guard let item else { return }

        let formattedDown = Self.formatSlot(downText, targetLength: 10)
        let formattedUp = Self.formatSlot(upText, targetLength: 10)

        let attrStr = NSMutableAttributedString()
        attrStr.append(NSAttributedString(
            string: "↓ \(formattedDown)   ",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: downColor,
            ]
        ))
        attrStr.append(NSAttributedString(
            string: "↑ \(formattedUp)",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: upColor,
            ]
        ))
        item.attributedTitle = attrStr
    }

    // 关键改动：严格归一化到固定槽位字符宽度，在等宽字体下确保物理渲染像素宽度绝对恒定
    private static func formatSlot(_ text: String, targetLength: Int = 10) -> String {
        var str = text
        // 若超出目标长度（例如 1023.9 MB/s 占 11 字符），通过去除小数点后一位紧凑化为 1023 MB/s
        if str.count > targetLength && str.contains(".") {
            if let dotIdx = str.firstIndex(of: "."), let spaceIdx = str.firstIndex(of: " "), dotIdx < spaceIdx {
                str.removeSubrange(dotIdx..<spaceIdx)
            }
        }
        let count = str.count
        if count >= targetLength {
            return str
        }
        return String(repeating: " ", count: targetLength - count) + str
    }

    // Returns GPU core count from IOKit registry (Apple Silicon: e.g. 32 for M1 Max).
    // Falls back to 0 if unavailable.
    private static func gpuCount() -> Int {
        let matching = IOServiceMatching("IOAccelerator")
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        var entry: io_object_t = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            if let n = IORegistryEntrySearchCFProperty(
                entry, kIOServicePlane,
                "gpu-core-count" as CFString,
                kCFAllocatorDefault,
                IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
            ) as? NSNumber {
                return n.intValue
            }
        }
        return 0
    }
}

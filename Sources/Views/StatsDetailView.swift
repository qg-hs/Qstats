import AppKit
import IOKit

/// 构建并实时更新状态栏下拉详情菜单（SF Symbol 图标、中文本地化、紧凑右对齐排版及流向着色）
final class StatsMenuBuilder {
    private var cpuItem: NSMenuItem?
    private var memoryItem: NSMenuItem?
    private var gpuItem: NSMenuItem?
    private var downItem: NSMenuItem?
    private var upItem: NSMenuItem?

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
        downItem = nil
        upItem = nil

        // 顶部品牌标题头（紧凑字号，避免横向撑大菜单）
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0"
        let headerItem = NSMenuItem(title: "Qstats", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false

        let headerStr = NSMutableAttributedString()
        headerStr.append(NSAttributedString(
            string: "Qstats",
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: NSColor.labelColor,
            ]
        ))
        headerStr.append(NSAttributedString(
            string: "  v\(version)",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor,
            ]
        ))
        headerItem.attributedTitle = headerStr
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

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
        if config.showNetwork {
            menu.addItem(NSMenuItem.separator())
            downItem = makeRow(icon: "arrow.down.circle", label: "下载", value: "—")
            menu.addItem(downItem!)
            upItem = makeRow(icon: "arrow.up.circle", label: "上传", value: "—")
            menu.addItem(upItem!)
        }

        menu.addItem(NSMenuItem.separator())
    }

    func update(snapshot: StatsSnapshot) {
        let cpuVal = String(format: "%.1f%%", snapshot.cpu)
        updateItem(cpuItem, label: cpuLabel, value: cpuVal,
                   valueColor: snapshot.cpu >= 80 ? .systemOrange : .secondaryLabelColor)

        let memVal = String(format: "%.1f / %.1f GB (%.0f%%)",
                            snapshot.memory.usedGB, snapshot.memory.totalGB, snapshot.memory.percentage)
        updateItem(memoryItem, label: "内存", value: memVal,
                   valueColor: snapshot.memory.percentage >= 85 ? .systemOrange : .secondaryLabelColor)

        let gpuVal = snapshot.gpu >= 0 ? String(format: "%.1f%%", snapshot.gpu) : "不可用"
        updateItem(gpuItem, label: gpuLabel, value: gpuVal, valueColor: .secondaryLabelColor)

        // 实时同步专属冷暖色谱，下载天蓝/极速青绿，上传暖黄/鲜橙/玫瑰粉
        let downColor = NetworkWidget.downloadColor(forBytesPerSec: snapshot.network.bytesInPerSec)
        updateItem(downItem, label: "下载", value: snapshot.network.formattedIn, valueColor: downColor)

        let upColor = NetworkWidget.uploadColor(forBytesPerSec: snapshot.network.bytesOutPerSec)
        updateItem(upItem, label: "上传", value: snapshot.network.formattedOut, valueColor: upColor)
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

    // 关键改动：优化制表位宽度为 160pt（此前 230pt 过宽导致横向冗余撑大），实现紧凑精致右对齐
    private func updateItem(_ item: NSMenuItem?, label: String, value: String, valueColor: NSColor = .secondaryLabelColor) {
        guard let item else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [
            NSTextTab(textAlignment: .right, location: 160, options: [:])
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
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: valueColor,
                .paragraphStyle: paragraph,
            ]
        ))
        item.attributedTitle = attrStr
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

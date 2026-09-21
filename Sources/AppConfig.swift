import Foundation
import AppKit

/// App configuration loaded from ~/.config/qstats/config.yaml
/// Hand-rolled flat YAML parser — no external dependency.
struct AppConfig {
    var cpuInterval: TimeInterval = 2.0
    var memoryInterval: TimeInterval = 2.0
    var gpuInterval: TimeInterval = 6.0
    var networkInterval: TimeInterval = 2.0
    var showCPU: Bool = true
    var showMemory: Bool = true
    var showGPU: Bool = true
    var showNetwork: Bool = true

    // Widget style: circle | bar | vbar | text
    var cpuStyle: String = "circle"
    var memoryStyle: String = "circle"
    var gpuStyle: String = "circle"

    // Widget colors: green | orange | blue | red | purple | yellow | pink | teal
    var cpuColor: String = "green"
    var memoryColor: String = "orange"
    var gpuColor: String = "purple"

    // SF Symbol names — see developer.apple.com/sf-symbols
    var cpuIcon: String = "cpu"
    var memoryIcon: String = "memorychip"
    var gpuIcon: String = "display"
    var networkIcon: String = "network"

    static func color(for name: String) -> NSColor {
        switch name {
        case "orange": return .systemOrange
        case "blue":   return .systemBlue
        case "red":    return .systemRed
        case "purple": return .systemPurple
        case "yellow": return .systemYellow
        case "pink":   return .systemPink
        case "teal":   return .systemTeal
        default:       return .systemGreen
        }
    }

    static let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/qstats")
    static let configPath = configDir.appendingPathComponent("config.yaml")

    /// Load config from disk, falling back to defaults for missing keys.
    static func load(from path: URL = configPath) -> AppConfig {
        var config = AppConfig()

        guard let data = try? Data(contentsOf: path),
              let text = String(data: data, encoding: .utf8) else {
            return config
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Strip inline comments and skip empty/comment lines
            let stripped = trimmed.hasPrefix("#") ? "" : String(trimmed.prefix(while: { $0 != "#" }))
                .trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty { continue }

            guard let colonIndex = stripped.firstIndex(of: ":") else { continue }
            let key = stripped[stripped.startIndex..<colonIndex]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
            // Preserve case for icon values (SF Symbol names are case-sensitive)
            let rawValue = stripped[stripped.index(after: colonIndex)...]
                .trimmingCharacters(in: .whitespaces)

            switch key {
            case "cpu_interval":
                if let v = Double(rawValue), v.isFinite, v >= 0.5 { config.cpuInterval = v }
            case "memory_interval":
                if let v = Double(rawValue), v.isFinite, v >= 0.5 { config.memoryInterval = v }
            case "gpu_interval":
                if let v = Double(rawValue), v.isFinite, v >= 1.0 { config.gpuInterval = v }
            case "network_interval":
                if let v = Double(rawValue), v.isFinite, v >= 0.5 { config.networkInterval = v }
            case "show_cpu":
                if let value = Bool(rawValue.lowercased()) { config.showCPU = value }
            case "show_memory":
                if let value = Bool(rawValue.lowercased()) { config.showMemory = value }
            case "show_gpu":
                if let value = Bool(rawValue.lowercased()) { config.showGPU = value }
            case "show_network":
                if let value = Bool(rawValue.lowercased()) { config.showNetwork = value }
            case "cpu_icon":
                if !rawValue.isEmpty { config.cpuIcon = rawValue }
            case "memory_icon":
                if !rawValue.isEmpty { config.memoryIcon = rawValue }
            case "gpu_icon":
                if !rawValue.isEmpty { config.gpuIcon = rawValue }
            case "network_icon":
                if !rawValue.isEmpty { config.networkIcon = rawValue }
            case "cpu_style":
                if !rawValue.isEmpty { config.cpuStyle = rawValue.lowercased() }
            case "memory_style":
                if !rawValue.isEmpty { config.memoryStyle = rawValue.lowercased() }
            case "gpu_style":
                if !rawValue.isEmpty { config.gpuStyle = rawValue.lowercased() }
            case "cpu_color":
                if !rawValue.isEmpty { config.cpuColor = rawValue.lowercased() }
            case "memory_color":
                if !rawValue.isEmpty { config.memoryColor = rawValue.lowercased() }
            case "gpu_color":
                if !rawValue.isEmpty { config.gpuColor = rawValue.lowercased() }
            default:
                break
            }
        }

        config.ensureVisibleMetric()
        return config
    }

    var visibleMetricCount: Int {
        [showNetwork, showCPU, showMemory, showGPU].filter { $0 }.count
    }

    mutating func ensureVisibleMetric() {
        if visibleMetricCount == 0 { showNetwork = true }
    }

    func isVisible(_ metric: Metric) -> Bool {
        switch metric {
        case .network: return showNetwork
        case .cpu: return showCPU
        case .memory: return showMemory
        case .gpu: return showGPU
        }
    }

    @discardableResult
    mutating func toggle(_ metric: Metric) -> Bool {
        guard !isVisible(metric) || visibleMetricCount > 1 else { return false }
        switch metric {
        case .network: showNetwork.toggle()
        case .cpu: showCPU.toggle()
        case .memory: showMemory.toggle()
        case .gpu: showGPU.toggle()
        }
        return true
    }

    func style(for metric: Metric) -> String {
        switch metric {
        case .cpu: return cpuStyle
        case .memory: return memoryStyle
        case .gpu: return gpuStyle
        case .network: return "text"
        }
    }

    mutating func setStyle(_ style: String, for metric: Metric) {
        switch metric {
        case .cpu: cpuStyle = style
        case .memory: memoryStyle = style
        case .gpu: gpuStyle = style
        case .network: break
        }
    }

    /// Persist only UI-managed keys, preserving comments and advanced settings.
    func saveDisplayPreferences(to path: URL = configPath) throws {
        let values = [
            "show_network": String(showNetwork), "show_cpu": String(showCPU),
            "show_memory": String(showMemory), "show_gpu": String(showGPU),
            "cpu_style": cpuStyle, "memory_style": memoryStyle, "gpu_style": gpuStyle
        ]
        let original = try String(contentsOf: path, encoding: .utf8)
        var remaining = values
        var lines = original.components(separatedBy: "\n").map { line -> String in
            guard let colon = line.firstIndex(of: ":") else { return line }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard let value = values[key] else { return line }
            remaining.removeValue(forKey: key)
            let comment = line.firstIndex(of: "#").map { "  " + line[$0...] } ?? ""
            return "\(key): \(value)\(comment)"
        }
        lines += remaining.keys.sorted().map { "\($0): \(remaining[$0]!)" }
        try lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
    }

    /// Write default config file if none exists. Creates ~/.config/qstats/ if needed.
    static func createDefaultIfNeeded() {
        let fm = FileManager.default
        if fm.fileExists(atPath: configPath.path) { return }

        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)

        // Copy legacy preferences once; check stats then osx-stats-nano
        let legacyStatsPath = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/stats/config.yaml")
        if fm.fileExists(atPath: legacyStatsPath.path),
           (try? fm.copyItem(at: legacyStatsPath, to: configPath)) != nil { return }

        let legacyNanoPath = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/osx-stats-nano/config.yaml")
        if fm.fileExists(atPath: legacyNanoPath.path),
           (try? fm.copyItem(at: legacyNanoPath, to: configPath)) != nil { return }

        let defaultYAML = """
        # ─────────────────────────────────────────
        # Qstats — Configuration
        # ─────────────────────────────────────────
        # Display/style settings can be changed live from the menu.
        # Restart after editing this file manually.

        # ── Polling intervals (seconds) ──────────
        # Minimum: 0.5s (gpu minimum: 1.0s)
        # GPU uses IOKit which is heavier — 6s recommended.

        cpu_interval: 2.0      # default: 2.0
        memory_interval: 2.0   # default: 2.0
        gpu_interval: 6.0      # default: 6.0
        network_interval: 2.0  # default: 2.0

        # ── Visibility ───────────────────────────
        # Options: true | false

        show_cpu: true         # default: true
        show_memory: true      # default: true
        show_gpu: true         # default: true
        show_network: true     # default: true

        # ── Widget style ─────────────────────────
        # Options: circle | bar | vbar | text

        cpu_style: circle      # default: circle
        memory_style: circle   # default: circle
        gpu_style: circle      # default: circle

        # ── Widget color ─────────────────────────
        # Options: green | orange | blue | red | purple | yellow | pink | teal

        cpu_color: green       # default: green
        memory_color: orange   # default: orange
        gpu_color: purple      # default: purple

        # ── Icons (SF Symbol names) ───────────────
        # Browse symbols at: developer.apple.com/sf-symbols
        # cpu:     cpu | cpu.fill | bolt | bolt.fill
        # memory:  memorychip | memorychip.fill
        # gpu:     display | display.fill | rectangle.3.group
        # network: network | wifi | antenna.radiowaves.left.and.right

        cpu_icon: cpu
        memory_icon: memorychip
        gpu_icon: display
        network_icon: network
        """

        try? defaultYAML.write(to: configPath, atomically: true, encoding: .utf8)
    }
}

/// Order matches the menu bar from left to right.
enum Metric: String, CaseIterable {
    case network, cpu, memory, gpu

    var title: String {
        switch self {
        case .network: return "网络速度"
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .gpu: return "GPU"
        }
    }
}

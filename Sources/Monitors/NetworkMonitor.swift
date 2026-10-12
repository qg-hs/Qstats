import CoreFoundation
import Darwin

struct NetworkThroughput {
    let bytesInPerSec: UInt64
    let bytesOutPerSec: UInt64

    var formattedIn: String { Self.format(bytesPerSec: bytesInPerSec) }
    var formattedOut: String { Self.format(bytesPerSec: bytesOutPerSec) }

    /// 高精度防抖动网络流速格式化（彻底消除浮点精度丢失、多位长尾小数与 1024KB/s 临界突变）
    static func format(bytesPerSec: UInt64) -> String {
        // 1. 临界防护：1 KB = 1024 字节。当小于 1023.5 KB (1,048,064 字节) 时显示为整数 KB/s，杜绝出现小数
        let kbBoundary: UInt64 = 1024 * 1024 - 512 // 1,048,064 字节
        if bytesPerSec < kbBoundary {
            let kb = Double(bytesPerSec) / 1024.0
            return String(format: "%.0f KB/s", kb)
        }

        // 2. 当介于 1023.5 KB 至 1023.95 MB 时，平滑进入 MB/s，严格锁定 1 位小数
        let mbBoundary: UInt64 = 1024 * 1024 * 1024 - 524288 // 1,073,217,536 字节
        if bytesPerSec < mbBoundary {
            let mb = Double(bytesPerSec) / (1024.0 * 1024.0)
            return String(format: "%.1f MB/s", mb)
        }

        // 3. 超过 1023.95 MB 时平滑升级为 GB/s，严格锁定 1 位小数
        let gb = Double(bytesPerSec) / (1024.0 * 1024.0 * 1024.0)
        return String(format: "%.1f GB/s", gb)
    }
}

final class NetworkMonitor {
    private var previousBytes: (inBytes: UInt64, outBytes: UInt64)?
    private var previousTime: CFAbsoluteTime?

    func reset() {
        previousBytes = nil
        previousTime = nil
    }

    func currentThroughput() -> NetworkThroughput {
        let current = readTotalBytes()
        let now = CFAbsoluteTimeGetCurrent()

        defer {
            previousBytes = current
            previousTime = now
        }

        guard let prev = previousBytes, let prevTime = previousTime else {
            return NetworkThroughput(bytesInPerSec: 0, bytesOutPerSec: 0)
        }

        let elapsed = now - prevTime
        // 边界防护：时间采样异常（系统休眠唤醒、时间漂移等）重置采样基准并安全归零
        guard elapsed >= 0.05 && elapsed <= 30.0 else {
            return NetworkThroughput(bytesInPerSec: 0, bytesOutPerSec: 0)
        }

        // 边界防护：防止网卡计数器重置、重连休眠唤醒导致的无符号整数溢出（消除几百亿或浮点溢出伪影）
        guard current.inBytes >= prev.inBytes && current.outBytes >= prev.outBytes else {
            return NetworkThroughput(bytesInPerSec: 0, bytesOutPerSec: 0)
        }

        let inDelta = current.inBytes - prev.inBytes
        let outDelta = current.outBytes - prev.outBytes

        // 合理性限幅（Sanity Check）：单个周期超过 100Gbps (12.5GB/s) 视为硬件计数器异常，截断安全保护
        let maxReasonableRate: UInt64 = 12_500_000_000
        let inRate = UInt64(Double(inDelta) / elapsed)
        let outRate = UInt64(Double(outDelta) / elapsed)

        return NetworkThroughput(
            bytesInPerSec: min(inRate, maxReasonableRate),
            bytesOutPerSec: min(outRate, maxReasonableRate)
        )
    }

    private func readTotalBytes() -> (inBytes: UInt64, outBytes: UInt64) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else { return (0, 0) }
        defer { freeifaddrs(ifaddr) }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var ptr = ifaddr

        while let current = ptr {
            defer { ptr = current.pointee.ifa_next }

            guard current.pointee.ifa_addr.pointee.sa_family == UInt8(AF_LINK) else { continue }

            // Skip loopback — strcmp avoids Swift String allocation
            guard strcmp(current.pointee.ifa_name, "lo0") != 0 else { continue }

            if let data = current.pointee.ifa_data {
                let ifData = data.assumingMemoryBound(to: if_data.self)
                totalIn += UInt64(ifData.pointee.ifi_ibytes)
                totalOut += UInt64(ifData.pointee.ifi_obytes)
            }
        }

        return (totalIn, totalOut)
    }
}

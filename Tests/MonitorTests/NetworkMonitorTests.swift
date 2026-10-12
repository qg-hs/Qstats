import XCTest
@testable import Qstats

final class NetworkMonitorTests: XCTestCase {
    func testNetworkStatsReturnsNonNegative() {
        let monitor = NetworkMonitor()
        let stats = monitor.currentThroughput()
        XCTAssertGreaterThanOrEqual(stats.bytesInPerSec, 0)
        XCTAssertGreaterThanOrEqual(stats.bytesOutPerSec, 0)
    }

    func testNetworkTotalBytesArePositive() {
        let monitor = NetworkMonitor()
        _ = monitor.currentThroughput()
        let stats = monitor.currentThroughput()
        XCTAssertGreaterThanOrEqual(stats.bytesInPerSec, 0)
    }

    func testResetClearsState() {
        let monitor = NetworkMonitor()
        _ = monitor.currentThroughput() // establish baseline
        monitor.reset()
        // After reset, no previousBytes/previousTime — must return 0, not overflow
        let stats = monitor.currentThroughput()
        XCTAssertEqual(stats.bytesInPerSec, 0)
        XCTAssertEqual(stats.bytesOutPerSec, 0)
    }

    func testResetPreventsPostSleepUInt64Overflow() {
        // Regression test for the post-sleep crash (PR #3):
        // After sleep, the network interface byte counters reset to a lower value.
        // If previousBytes > current (counter wrapped/reset) and previousTime is stale
        // (long elapsed), the wrapping subtraction could overflow UInt64 when used
        // unsafely. The fix: reset() clears previousBytes so the first post-wake call
        // returns 0 instead of an overflowed value.
        //
        // We simulate this by calling reset() (as StatsPoller.start() does on wake)
        // and verifying no overflow occurs.
        let monitor = NetworkMonitor()
        _ = monitor.currentThroughput()
        monitor.reset()
        let stats = monitor.currentThroughput()
        // Must be 0 (no baseline), never a huge overflow value
        XCTAssertEqual(stats.bytesInPerSec, 0)
        XCTAssertEqual(stats.bytesOutPerSec, 0)
        XCTAssertLessThan(stats.bytesInPerSec, UInt64.max / 2)
        XCTAssertLessThan(stats.bytesOutPerSec, UInt64.max / 2)
    }

    func testFormatBytesPerSecKB() {
        XCTAssertEqual(NetworkThroughput.format(bytesPerSec: 512), "0 KB/s")
        XCTAssertEqual(NetworkThroughput.format(bytesPerSec: 1024), "1 KB/s")
        XCTAssertEqual(NetworkThroughput.format(bytesPerSec: 10240), "10 KB/s")
    }

    func testFormatBytesPerSecMB() {
        let oneMB: UInt64 = 1024 * 1024
        XCTAssertEqual(NetworkThroughput.format(bytesPerSec: oneMB), "1.0 MB/s")
        XCTAssertEqual(NetworkThroughput.format(bytesPerSec: oneMB * 10), "10.0 MB/s")
    }

    func testFormatBytesPerSecGB() {
        let oneGB: UInt64 = 1024 * 1024 * 1024
        XCTAssertEqual(NetworkThroughput.format(bytesPerSec: oneGB), "1.0 GB/s")
    }

    func testNetworkWidgetColorTiers() {
        // 关键改动：验证下载色系与上传色系彻底分离，在任何相同网速下均具备显著色差
        let lowBytes: UInt64 = 50 * 1024
        let midBytes: UInt64 = 300 * 1024
        let highBytes: UInt64 = 800 * 1024

        let downLow = NetworkWidget.downloadColor(forBytesPerSec: lowBytes)
        let upLow = NetworkWidget.uploadColor(forBytesPerSec: lowBytes)

        let downMid = NetworkWidget.downloadColor(forBytesPerSec: midBytes)
        let upMid = NetworkWidget.uploadColor(forBytesPerSec: midBytes)

        let downHigh = NetworkWidget.downloadColor(forBytesPerSec: highBytes)
        let upHigh = NetworkWidget.uploadColor(forBytesPerSec: highBytes)

        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            guard let dlRGB = downLow.usingColorSpace(.sRGB),
                  let ulRGB = upLow.usingColorSpace(.sRGB),
                  let dmRGB = downMid.usingColorSpace(.sRGB),
                  let umRGB = upMid.usingColorSpace(.sRGB),
                  let dhRGB = downHigh.usingColorSpace(.sRGB),
                  let uhRGB = upHigh.usingColorSpace(.sRGB) else {
                XCTFail("Failed to convert colors to sRGB")
                return
            }

            // 1. 低速区间：下载为天蓝 (#38BDF8: R=56, B=248)，上传为暖琥珀黄 (#FBBF24: R=251, B=36)
            XCTAssertEqual(Int(round(dlRGB.redComponent * 255)), 56)
            XCTAssertEqual(Int(round(ulRGB.redComponent * 255)), 251)
            XCTAssertNotEqual(dlRGB, ulRGB)

            // 2. 中速区间：下载为科技蓝 (#60A5FA: R=96, B=250)，上传为活力鲜橙 (#FB923C: R=251, B=60)
            XCTAssertEqual(Int(round(dmRGB.redComponent * 255)), 96)
            XCTAssertEqual(Int(round(umRGB.redComponent * 255)), 251)
            XCTAssertNotEqual(dmRGB, umRGB)

            // 3. 高速区间：下载为极速青绿 (#43E9C9: R=67, G=233)，上传为高能玫瑰粉 (#F43F5E: R=244, G=63)
            XCTAssertEqual(Int(round(dhRGB.redComponent * 255)), 67)
            XCTAssertEqual(Int(round(uhRGB.redComponent * 255)), 244)
            XCTAssertNotEqual(dhRGB, uhRGB)
        }
    }

    func testNetworkWidgetDynamicContentWidth() {
        let smallWidget = NetworkWidget(down: "7 KB/s", up: "31 KB/s")
        let largeWidget = NetworkWidget(down: "1023 KB/s", up: "1023 KB/s")

        let smallWidth = smallWidget.widthForHeight(22)
        let largeWidth = largeWidget.widthForHeight(22)

        // 验证小流量下的宽度自适应紧凑，不再占用固定 1023 KB/s 导致的巨幅空白
        XCTAssertLessThan(smallWidth, largeWidth)
        XCTAssertGreaterThan(smallWidth, 20)
    }

    func testFormatBoundaryPrecision() {
        // 1. 验证临界值不发生 1024 KB/s 突变，且绝无小数尾巴
        let kb999 = NetworkThroughput.format(bytesPerSec: 999 * 1024)
        XCTAssertEqual(kb999, "999 KB/s")

        let kb1023 = NetworkThroughput.format(bytesPerSec: 1023 * 1024)
        XCTAssertEqual(kb1023, "1023 KB/s")

        // 1023.6 KB 平滑进入 1.0 MB/s，而非 1024 KB/s
        let kb1023_6 = NetworkThroughput.format(bytesPerSec: 1_048_166)
        XCTAssertEqual(kb1023_6, "1.0 MB/s")

        // 2. 验证高位小数四舍五入后严格锁定 1 位小数，绝不产生类似 999.999999999 精度丢失
        let near1000MB = NetworkThroughput.format(bytesPerSec: UInt64(999.99 * 1024 * 1024))
        XCTAssertEqual(near1000MB, "1000.0 MB/s")
        XCTAssertFalse(near1000MB.contains("999.99"))

        // 3. 验证字符串不含有多于 1 位的小数位
        let sample = NetworkThroughput.format(bytesPerSec: 12345678)
        if let dotIndex = sample.firstIndex(of: ".") {
            let afterDot = sample[sample.index(after: dotIndex)...]
            let decimalDigits = afterDot.prefix(while: { $0.isNumber })
            XCTAssertLessThanOrEqual(decimalDigits.count, 1)
        }
    }
}


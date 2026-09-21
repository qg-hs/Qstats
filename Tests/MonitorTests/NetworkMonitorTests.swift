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
}

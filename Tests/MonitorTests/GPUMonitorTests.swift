import XCTest
@testable import Qstats

final class GPUMonitorTests: XCTestCase {
    func testGPUUsageReturnsValidPercentage() {
        let monitor = GPUMonitor()
        let usage = monitor.currentUsage()
        // GPU may not be available in all environments, so -1 means unavailable
        if usage >= 0 {
            XCTAssertLessThanOrEqual(usage, 100.0)
        }
    }
}

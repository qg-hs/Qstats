import XCTest
@testable import Qstats

final class AppConfigTests: XCTestCase {
    func testFreshInstallShowsAllMetrics() {
        XCTAssertEqual(AppConfig().visibleMetricCount, 4)
    }

    func testEveryNonemptySelectionCanBeReachedAndLastMetricCannotBeHidden() {
        for mask in 1..<16 {
            var config = AppConfig()
            for (index, metric) in Metric.allCases.enumerated() where mask & (1 << index) == 0 {
                XCTAssertTrue(config.toggle(metric))
            }
            XCTAssertEqual(config.visibleMetricCount, mask.nonzeroBitCount)
            for (index, metric) in Metric.allCases.enumerated() {
                XCTAssertEqual(config.isVisible(metric), mask & (1 << index) != 0)
            }
            if config.visibleMetricCount == 1 {
                let last = Metric.allCases.first { config.isVisible($0) }!
                XCTAssertFalse(config.toggle(last))
                XCTAssertEqual(config.visibleMetricCount, 1)
            }
        }
    }

    func testDisplayPreferencesRoundTripPreservesAdvancedConfiguration() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        try "# custom config\ncpu_interval: 3.5\ncpu_color: teal\nshow_cpu: true # keep comment\nfuture_setting: value\n".write(to: path, atomically: true, encoding: .utf8)
        var config = AppConfig.load(from: path)
        config.showCPU = false
        config.showGPU = false
        config.memoryStyle = "text"
        try config.saveDisplayPreferences(to: path)
        let loaded = AppConfig.load(from: path)
        XCTAssertFalse(loaded.showCPU)
        XCTAssertFalse(loaded.showGPU)
        XCTAssertTrue(loaded.showNetwork)
        XCTAssertEqual(loaded.memoryStyle, "text")
        XCTAssertEqual(loaded.cpuInterval, 3.5)
        XCTAssertEqual(loaded.cpuColor, "teal")
        let text = try String(contentsOf: path)
        XCTAssertTrue(text.contains("# keep comment"))
        XCTAssertTrue(text.contains("future_setting: value"))
    }

    func testEmptySelectionAndInvalidValuesRecoverSafely() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        try "show_cpu: false\nshow_memory: false\nshow_gpu: false\nshow_network: false\ncpu_interval: inf\n".write(to: path, atomically: true, encoding: .utf8)
        let config = AppConfig.load(from: path)
        XCTAssertTrue(config.showNetwork)
        XCTAssertEqual(config.visibleMetricCount, 1)
        XCTAssertEqual(config.cpuInterval, 2)
    }
}

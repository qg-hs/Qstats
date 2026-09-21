import AppKit
import XCTest
@testable import Qstats

final class StatusBarViewTests: XCTestCase {
    func testAllSelectionsRemainVisibleIncludingUnavailableGPU() {
        for mask in 1..<16 {
            var config = AppConfig()
            for (index, metric) in Metric.allCases.enumerated() where mask & (1 << index) == 0 {
                config.toggle(metric)
            }
            let view = StatusBarView(config: config)
            view.rebuildWidgets() // .empty includes unavailable GPU
            XCTAssertGreaterThan(view.cachedWidth, 12)
            XCTAssertLessThan(view.cachedWidth, 260)
            if mask != 15 {
                view.apply(config: AppConfig())
                view.rebuildWidgets()
                let fullWidth = view.cachedWidth
                view.apply(config: config)
                view.rebuildWidgets()
                XCTAssertLessThan(view.cachedWidth, fullWidth)
            }
        }
    }

    func testRenderStylePreviewsInBothAppearances() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/widget-previews")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for style in ["circle", "bar", "vbar", "text"] {
                var config = AppConfig()
                config.cpuStyle = style
                config.memoryStyle = style
                config.gpuStyle = style
                let view = StatusBarView(config: config)
                view.snapshot = StatsSnapshot(cpu: 32, memory: MemoryStats(totalBytes: 16_000_000_000, usedBytes: 9_000_000_000), gpu: 18,
                    network: NetworkThroughput(bytesInPerSec: 245_000, bytesOutPerSec: 12_000))
                view.rebuildWidgets()
                view.frame = NSRect(x: 0, y: 0, width: view.cachedWidth, height: 24)
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.cachedWidth * 2), pixelsHigh: 48,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                bitmap.size = view.frame.size
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                    NSColor.windowBackgroundColor.setFill()
                    view.bounds.fill()
                    view.draw(view.bounds)
                }
                NSGraphicsContext.restoreGraphicsState()
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("\(style)-\(appearance.rawValue).png"))
            }
        }
    }
}

import AppKit
import Carbon.HIToolbox
import XCTest
@testable import Qstats

final class ScreenshotTests: XCTestCase {
    func testDefaultScreenshotShortcutIsOptionD() {
        XCTAssertEqual(KeyboardShortcut.defaultScreenshot.keyCode, UInt32(kVK_ANSI_D))
        XCTAssertEqual(KeyboardShortcut.defaultScreenshot.modifiers, UInt32(optionKey))
        XCTAssertEqual(KeyboardShortcut.defaultScreenshot.displayName, "⌥D")
    }

    func testShortcutDisplayUsesMacModifierOrder() {
        let shortcut = KeyboardShortcut(
            keyCode: UInt32(kVK_ANSI_2),
            modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey)
        )
        XCTAssertEqual(shortcut.displayName, "⌃⌥⇧⌘2")
        XCTAssertTrue(shortcut.isValid)
    }

    func testShortcutPreferencesRoundTrip() throws {
        let suiteName = "stats.tests.shortcut.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let shortcut = KeyboardShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(controlKey | shiftKey))
        ShortcutPreferences.save(shortcut, to: defaults)
        XCTAssertEqual(ShortcutPreferences.load(from: defaults), shortcut)
    }

    func testNormalizedRectSupportsEveryDragDirection() {
        let expected = NSRect(x: 10, y: 20, width: 30, height: 40)
        XCTAssertEqual(normalizedRect(from: NSPoint(x: 10, y: 20), to: NSPoint(x: 40, y: 60)), expected)
        XCTAssertEqual(normalizedRect(from: NSPoint(x: 40, y: 60), to: NSPoint(x: 10, y: 20)), expected)
        XCTAssertEqual(normalizedRect(from: NSPoint(x: 10, y: 60), to: NSPoint(x: 40, y: 20)), expected)
        XCTAssertEqual(normalizedRect(from: NSPoint(x: 40, y: 20), to: NSPoint(x: 10, y: 60)), expected)
    }

    func testAnnotationToolsHaveUniqueSymbolsAndTitles() {
        XCTAssertEqual(Set(AnnotationTool.allCases.map(\.symbolName)).count, AnnotationTool.allCases.count)
        XCTAssertTrue(AnnotationTool.allCases.allSatisfy { !$0.title.isEmpty })
    }

    func testShapeAnnotationsRenderPixels() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 120,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 120).fill()
        let annotations: [Annotation] = [
            .rectangle(rect: NSRect(x: 8, y: 8, width: 80, height: 50), color: .systemRed, width: 4),
            .arrow(start: NSPoint(x: 20, y: 20), end: NSPoint(x: 150, y: 90), color: .systemBlue, width: 4),
            .pen(points: [NSPoint(x: 10, y: 100), NSPoint(x: 80, y: 70), NSPoint(x: 180, y: 110)], color: .white, width: 3),
            .text(origin: NSPoint(x: 100, y: 20), value: "stats", color: .systemGreen, size: 18)
        ]
        for annotation in annotations { annotation.draw(in: graphics.cgContext) }
        graphics.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 500)
    }

    func testSelectionHandleCountAndDiagonalCursors() {
        XCTAssertEqual(SelectionHandle.allCases.count, 8)
        XCTAssertNotNil(ScreenshotCursorFactory.resizeDiagonalNWSE)
        XCTAssertNotNil(ScreenshotCursorFactory.resizeDiagonalNESW)
    }

    func testColorPickerPresetsAreValidAndDistinct() {
        let presets = ScreenshotColorPickerView.presets
        XCTAssertGreaterThanOrEqual(presets.count, 10)
        let uniqueHex = Set(presets.compactMap { color -> String? in
            guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
            return String(format: "%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
        })
        XCTAssertEqual(uniqueHex.count, presets.count)
    }

    func testDesignTokensMatchConfiguredPalette() throws {
        let bg = try XCTUnwrap(ScreenshotDesignTokens.iconBg.usingColorSpace(.sRGB))
        XCTAssertEqual(Int(round(bg.redComponent * 255)), 10)
        XCTAssertEqual(Int(round(bg.greenComponent * 255)), 28)
        XCTAssertEqual(Int(round(bg.blueComponent * 255)), 63)

        let primary = try XCTUnwrap(ScreenshotDesignTokens.iconPrimary.usingColorSpace(.sRGB))
        XCTAssertEqual(Int(round(primary.redComponent * 255)), 67)
        XCTAssertEqual(Int(round(primary.greenComponent * 255)), 233)
        XCTAssertEqual(Int(round(primary.blueComponent * 255)), 201)
    }

    func testSizeSliderViewInitializationAndDynamicUpdate() {
        let slider = ScreenshotSizeSliderView(currentSize: 4.0, title: "画笔粗细")
        XCTAssertNotNil(slider)
        slider.updateSize(12.0)

        // 测试马赛克专用滑动条配置
        let mosaicSlider = ScreenshotSizeSliderView(
            currentSize: 16.0,
            title: "马赛克模糊度",
            minValue: 4.0,
            maxValue: 40.0,
            presets: [8, 14, 22, 32],
            unit: "阶"
        )
        XCTAssertNotNil(mosaicSlider)
        mosaicSlider.updateSize(24.0)
    }

    func testMosaicAnnotationCreationAndEnum() {
        let mosaic = Annotation.mosaic(rect: NSRect(x: 10, y: 10, width: 60, height: 60), scale: 20.0)
        if case let .mosaic(rect, scale) = mosaic {
            XCTAssertEqual(rect.width, 60)
            XCTAssertEqual(scale, 20.0)
        } else {
            XCTFail("Annotation must be .mosaic")
        }
    }
}

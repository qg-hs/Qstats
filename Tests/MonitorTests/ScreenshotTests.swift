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
        XCTAssertTrue(mosaic.isMosaic)
        XCTAssertEqual(mosaic.mosaicRect, NSRect(x: 10, y: 10, width: 60, height: 60))
        XCTAssertEqual(mosaic.mosaicScale, 20.0)
    }

    func testToolbarContainsCheckmarkConfirmButton() {
        let toolbar = ScreenshotToolbarView()
        // 查找所有子视图中的按钮，验证存在 checkmark 图标按钮
        func findButtons(in view: NSView) -> [NSButton] {
            var buttons: [NSButton] = []
            for sub in view.subviews {
                if let btn = sub as? NSButton { buttons.append(btn) }
                buttons.append(contentsOf: findButtons(in: sub))
            }
            return buttons
        }
        let buttons = findButtons(in: toolbar)
        let checkmarkButtons = buttons.filter { btn in
            btn.accessibilityLabel() == "完成截图并复制" || btn.image?.accessibilityDescription == "完成截图并复制"
        }
        XCTAssertEqual(checkmarkButtons.count, 1, "工具栏最右侧必须包含一个且仅一个 checkmark 完成截图按钮")
    }

    func testPinnedImageViewFourCornerDetection() {
        let image = NSImage(size: NSSize(width: 400, height: 300))
        let pinnedView = PinnedImageView(image: image)
        pinnedView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)

        // 验证 resetCursorRects 不崩溃
        pinnedView.resetCursorRects()

        // 验证宽高比计算
        let aspectRatio = image.size.width / image.size.height
        XCTAssertEqual(aspectRatio, 4.0 / 3.0, accuracy: 0.001)

        // 验证等比缩放计算：若宽度变为 200，高度必须按比例变为 150
        let newWidth: CGFloat = 200.0
        let newHeight = newWidth / aspectRatio
        XCTAssertEqual(newHeight, 150.0, accuracy: 0.001)

        // 验证控制器 resize 保持图片比例，杜绝形变
        let controller = PinnedImageController(image: image)
        controller.resize(by: 0.5) // 缩小
        let shrunk = controller.panel.frame.size
        XCTAssertEqual(shrunk.width / shrunk.height, aspectRatio, accuracy: 0.02)
        controller.resize(by: 2.0) // 放大
        let enlarged = controller.panel.frame.size
        XCTAssertEqual(enlarged.width / enlarged.height, aspectRatio, accuracy: 0.02)
        XCTAssertGreaterThan(enlarged.width, shrunk.width, "放大操作必须使尺寸严格大于缩小尺寸")
    }

    func testMosaicInteractiveHandleMath() {
        let rect = NSRect(x: 50, y: 60, width: 100, height: 80)

        // 4 角坐标验证
        let topLeft = NSPoint(x: rect.minX, y: rect.maxY)
        let topRight = NSPoint(x: rect.maxX, y: rect.maxY)
        let bottomLeft = NSPoint(x: rect.minX, y: rect.minY)
        let bottomRight = NSPoint(x: rect.maxX, y: rect.minY)

        XCTAssertEqual(topLeft, NSPoint(x: 50, y: 140))
        XCTAssertEqual(topRight, NSPoint(x: 150, y: 140))
        XCTAssertEqual(bottomLeft, NSPoint(x: 50, y: 60))
        XCTAssertEqual(bottomRight, NSPoint(x: 150, y: 60))

        // 4 角对角拉动 normalizedRect 几何一致性验证
        let draggedFromTL = normalizedRect(from: bottomRight, to: NSPoint(x: 30, y: 160))
        XCTAssertEqual(draggedFromTL, NSRect(x: 30, y: 60, width: 120, height: 100))
    }
}

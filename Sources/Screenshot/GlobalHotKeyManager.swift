import Carbon.HIToolbox
import Foundation

final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    // 区域截图回调
    var onScreenshot: (() -> Void)?
    // 关键改动：新增剪贴板贴图触发回调
    var onPinClipboard: (() -> Void)?

    private var screenshotHotKey: EventHotKeyRef?
    private var pinClipboardHotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private static let screenshotHotKeyID: UInt32 = 1
    private static let pinClipboardHotKeyID: UInt32 = 2

    private init() {}

    private func ensureEventHandlerInstalled() -> Bool {
        if handler != nil { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // 使用 GetEventDispatcherTarget 确保即使 NSMenu 弹出处于 TrackingRunLoop 模式时，快捷键事件依然由根派发器捕获
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var identifier = EventHotKeyID()
            let size = MemoryLayout<EventHotKeyID>.size
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID), nil, size, nil,
                                    &identifier) == noErr else { return noErr }
            if identifier.signature == GlobalHotKeyManager.signature {
                // 使用 kCFRunLoopCommonModes 调度主线程，避免被 NSEventTrackingRunLoopMode 挂起阻塞
                if identifier.id == GlobalHotKeyManager.screenshotHotKeyID {
                    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                        GlobalHotKeyManager.shared.onScreenshot?()
                    }
                    CFRunLoopWakeUp(CFRunLoopGetMain())
                } else if identifier.id == GlobalHotKeyManager.pinClipboardHotKeyID {
                    CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                        GlobalHotKeyManager.shared.onPinClipboard?()
                    }
                    CFRunLoopWakeUp(CFRunLoopGetMain())
                }
            }
            return noErr
        }, 1, &spec, nil, &handler)
        return status == noErr
    }

    // 关键改动：注册区域截图快捷键（ID: 1）
    @discardableResult
    func registerScreenshotShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        unregisterScreenshot()
        guard ensureEventHandlerInstalled() else { return false }

        let identifier = EventHotKeyID(signature: Self.signature, id: Self.screenshotHotKeyID)
        let registered = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier,
                                              GetEventDispatcherTarget(), 0, &screenshotHotKey) == noErr
        if !registered { unregisterScreenshot() }
        return registered
    }

    // 关键改动：注册剪贴板贴图快捷键（ID: 2）
    @discardableResult
    func registerPinClipboardShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        unregisterPinClipboard()
        guard ensureEventHandlerInstalled() else { return false }

        let identifier = EventHotKeyID(signature: Self.signature, id: Self.pinClipboardHotKeyID)
        let registered = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier,
                                              GetEventDispatcherTarget(), 0, &pinClipboardHotKey) == noErr
        if !registered { unregisterPinClipboard() }
        return registered
    }

    func unregisterScreenshot() {
        if let screenshotHotKey { UnregisterEventHotKey(screenshotHotKey) }
        screenshotHotKey = nil
    }

    func unregisterPinClipboard() {
        if let pinClipboardHotKey { UnregisterEventHotKey(pinClipboardHotKey) }
        pinClipboardHotKey = nil
    }

    func unregister() {
        unregisterScreenshot()
        unregisterPinClipboard()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    private static let signature: OSType = {
        Array("STAT".utf8).reduce(0) { ($0 << 8) | OSType($1) }
    }()
}

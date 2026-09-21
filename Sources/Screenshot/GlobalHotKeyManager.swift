import Carbon.HIToolbox
import Foundation

final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    var onScreenshot: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    private init() {}

    @discardableResult
    func registerScreenshotShortcut(_ shortcut: KeyboardShortcut) -> Bool {
        unregister()
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // 使用 GetEventDispatcherTarget 确保即使 NSMenu 弹出处于 TrackingRunLoop 模式时，快捷键事件依然由根派发器捕获
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ in
            var identifier = EventHotKeyID()
            let size = MemoryLayout<EventHotKeyID>.size
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID), nil, size, nil,
                                    &identifier) == noErr else { return noErr }
            if identifier.signature == GlobalHotKeyManager.signature && identifier.id == 1 {
                // 使用 kCFRunLoopCommonModes 调度主线程，避免被 NSEventTrackingRunLoopMode 挂起阻塞
                CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                    GlobalHotKeyManager.shared.onScreenshot?()
                }
                CFRunLoopWakeUp(CFRunLoopGetMain())
            }
            return noErr
        }, 1, &spec, nil, &handler)
        guard status == noErr else { return false }

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let registered = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, identifier,
                                              GetEventDispatcherTarget(), 0, &hotKey) == noErr
        if !registered { unregister() }
        return registered
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    private static let signature: OSType = {
        Array("STAT".utf8).reduce(0) { ($0 << 8) | OSType($1) }
    }()
}

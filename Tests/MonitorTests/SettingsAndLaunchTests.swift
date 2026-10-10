import XCTest
@testable import Qstats

final class SettingsAndLaunchTests: XCTestCase {
    func testLaunchAtLoginManagerSingleton() {
        let manager = LaunchAtLoginManager.shared
        XCTAssertNotNil(manager)
        // 状态描述必须包含有效字符串且不为空
        let desc = manager.statusDescription
        XCTAssertFalse(desc.isEmpty)
        XCTAssertTrue(["已启用", "未启用", "待系统批准", "未找到应用服务", "系统版本不支持", "未知状态"].contains(desc))
    }

    func testScreenCaptureServicePermissionInspection() {
        let service = ScreenCaptureService()
        // 检查权限调用不发生崩溃或死锁
        _ = service.hasPermission
        XCTAssertTrue(true)
    }
}

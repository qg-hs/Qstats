import Foundation
import ServiceManagement

/// macOS 开机自启动管理器（封装 SMAppService 原生服务，适配 macOS 13+）
final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    /// 当前开机自启动状态
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    /// 获取详细的系统自启状态描述
    var statusDescription: String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return "已启用"
            case .notRegistered:
                return "未启用"
            case .requiresApproval:
                return "待系统批准"
            case .notFound:
                return "未找到应用服务"
            @unknown default:
                return "未知状态"
            }
        }
        return "系统版本不支持"
    }

    /// 切换开机自启动状态
    /// - Parameter enabled: true 为开启，false 为关闭
    /// - Throws: 注册或注销失败时的系统错误
    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            let service = SMAppService.mainApp
            if enabled {
                if service.status == .enabled {
                    return
                }
                // 边界防御：尝试清理可能存在的失效状态后再注册
                if service.status == .requiresApproval {
                    try? service.unregister()
                }
                try service.register()
            } else {
                if service.status == .enabled || service.status == .requiresApproval {
                    try service.unregister()
                }
            }
        } else {
            throw NSError(
                domain: "LaunchAtLoginManager",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "当前系统版本低于 macOS 13.0，无法调用 SMAppService"]
            )
        }
    }
}

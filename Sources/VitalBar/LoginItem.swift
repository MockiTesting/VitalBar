// SPDX-License-Identifier: MIT

import Foundation
import ServiceManagement

/// 登录时启动。走 `SMAppService.mainApp`（macOS 13+）：app 自己注册成登录项，
/// 不需要 helper、不需要往 `~/Library/LaunchAgents` 写 plist，卸载时由系统一并清掉。
///
/// **状态不落自己的 preferences**，每次直接问系统：用户可能在
/// 「系统设置 → 通用 → 登录项」里把它关掉，自存一个 Bool 就会和真实状态打架
/// （界面显示“开”，实际已被系统关掉）。
enum LoginItem {
    /// 只有 `.enabled` 算开；`.requiresApproval` 是“用户/系统还没放行”，
    /// 对开关来说仍是没生效，所以不当作开。
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 返回 nil 表示成功，否则是给用户看的错误描述。
    /// 注册/注销都可能失败：没有签名、bundle 不在可注册位置、系统拒绝等。
    @discardableResult
    static func set(_ on: Bool) -> String? {
        let service = SMAppService.mainApp
        do {
            if on {
                // 已启用时再 register 会抛 "Operation already in progress"，
                // 而这个开关可能只是从系统设置同步回来的，不是用户点击。
                guard service.status != .enabled else { return nil }
                try service.register()
            } else {
                guard service.status != .notRegistered else { return nil }
                try service.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// 当前运行的 bundle 是否在 `/Applications` 下。登录项记的是**当前这个路径**：
    /// 从 `build/` 注册、之后装到 `/Applications`，登录项还指着旧路径（可能已被删）。
    static var runsFromApplications: Bool {
        Bundle.main.bundlePath.hasPrefix("/Applications/")
    }

    /// 给 `--login` 自检用的可读状态，避免在 main.swift 里再 import ServiceManagement。
    static var statusDescription: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "enabled"
        case .notRegistered: return "notRegistered"
        case .notFound: return "notFound"
        case .requiresApproval: return "requiresApproval"
        @unknown default: return "unknown"
        }
    }
}

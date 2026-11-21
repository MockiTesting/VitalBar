// SPDX-License-Identifier: MIT

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let status = StatusItemController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Dbg.log("launch args=\(CommandLine.arguments) bundle=\(Bundle.main.bundleIdentifier ?? "nil")")
        guard enforceSingleInstance() else { Dbg.log("single instance -> quit"); return }
        NSApp.setActivationPolicy(.accessory)
        status.install()
        // 调试入口：本机无法用脚本点击状态项，靠 --args 直接开面板
        let d = UserDefaults.standard
        let wantPopup = CommandLine.arguments.contains("--popup") || d.bool(forKey: "vitalbar.debugPopupOnce")
        let wantSettings = CommandLine.arguments.contains("--settings") || d.bool(forKey: "vitalbar.debugSettingsOnce")
        if d.bool(forKey: "vitalbar.debugPopupOnce") { d.set(false, forKey: "vitalbar.debugPopupOnce") }
        if d.bool(forKey: "vitalbar.debugSettingsOnce") { d.set(false, forKey: "vitalbar.debugSettingsOnce") }
        if CommandLine.arguments.contains("--panel") || d.bool(forKey: "vitalbar.debugPanelOnce") {
            if d.bool(forKey: "vitalbar.debugPanelOnce") { d.set(false, forKey: "vitalbar.debugPanelOnce") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [status] in status.debugPanelOnBuiltin() }
        }
        if wantPopup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [status] in status.debugOpenPopup() }
        }
        if wantSettings {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [status] in status.debugOpenSettings() }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// 单实例：保留最小 PID，新实例把旧实例叫到前面后自退。
    private func enforceSingleInstance() -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        // 从 bundle 动态读，不在代码里写死 id：以后改 Info.plist 不必再来改这里。
        // 取不到时（极少见）直接返回 true，宁可多跑一个实例也不要启动失败。
        guard let bid = Bundle.main.bundleIdentifier else { return true }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            .filter { $0.processIdentifier != me }
        guard let first = others.min(by: { $0.processIdentifier < $1.processIdentifier }) else { return true }
        first.activate(options: [.activateIgnoringOtherApps])
        NSApp.terminate(nil)
        return false
    }

    /// 外观覆盖只作用于**弹框与设置窗口**。
    ///
    /// 这里绝不能遍历 `NSApp.windows` 无差别设置：状态栏窗口（NSStatusBarWindow，level 25）
    /// 也在那个数组里，一旦给它套上 darkAqua，`button.effectiveAppearance` 就变深色，
    /// 状态项会画成白字——浅色菜单栏上直接不可见。popover 在打开时单独设置。
    static func applyLook() {
        for w in NSApp.windows {
            guard w.level.rawValue < 20, w.title.contains("VitalBar") else { continue }
            applyLook(to: w)
        }
    }

    /// **窗口与它的 contentView 必须一起改**，少改一个就会得到半深半浅的窗口：
    ///
    /// - 只改窗口：title bar 会跟着变，但 contentView 上那份更早写下的显式 NSAppearance
    ///   优先级高于窗口，正文不动——这正是「手动切深色，只有标题栏变色」的成因
    ///   （视图上显式设置的外观优先于从 window / superview 继承的那一份）。
    /// - 只改 contentView：正文变了，title bar 停在系统外观上（系统深色 + 选浅色时
    ///   就是「黑标题栏 + 白正文」）。
    ///
    /// 两个都设成同一个值之后，「窗口 chrome + SwiftUI 正文」才是一个整体。
    static func applyLook(to w: NSWindow) {
        let ap = Prefs.shared.look.appearance
        w.appearance = ap
        w.contentView?.appearance = ap
        // 外观换了要重画：SwiftUI 的 Color(nsColor:) 是动态色，但显示列表得被失效一次。
        w.contentView?.needsDisplay = true
    }
}

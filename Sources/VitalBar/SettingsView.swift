// SPDX-License-Identifier: MIT

import AppKit
import Combine
import SwiftUI

/// 设置页：全局外观 → 菜单栏内容 → 状态数据，从粗到细。
/// 三个开关同级、左对齐、互不置灰（唯一例外是无电池机型）。
/// 高度由内容撑开，窗口按 `fittingSize` 定尺寸——底部不留空白，只留一行版本号。
///
/// v1.2 只做「与新弹框同一套语言」，不加新设置项：
/// 换成 `panel` / `card` / `rule` / `ink1..3` 令牌，卡片圆角 12 → 10（与弹框的指标行一致），
/// 并在两条指标选择前各放一个 8 pt 身份色圆点——选中的指标在弹框里是什么颜色，
/// 这里就先看到什么颜色，不必再去弹框里对一遍。
struct SettingsView: View {
    @State private var look = Prefs.shared.look
    @State private var content = Prefs.shared.content
    @State private var layout = Prefs.shared.layout
    @State private var showSpeed = Prefs.shared.showSpeed
    @State private var showBatteryState = Prefs.shared.showBatteryState
    @State private var showBatteryPercent = Prefs.shared.showBatteryPercent
    @State private var slot1 = Prefs.shared.slot1
    @State private var slot2 = Prefs.shared.slot2
    @State private var memMetric = Prefs.shared.memMetric
    /// 登录项状态不存 UserDefaults，初值直接问系统（见 `LoginItem`）。
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?

    private var hasBattery: Bool { SamplerHub.shared.latest.battery.installed }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 0) {
                loginRow
                loginHint

                divider
                row("外观") {
                    Picker("", selection: $look) {
                        ForEach(Prefs.Look.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                    .onChange(of: look) { Prefs.shared.look = $0; AppDelegate.applyLook() }
                }
                hint("仅影响弹框与设置窗口；菜单栏图标始终跟随系统。")

                divider
                row("显示方式") {
                    Picker("", selection: $content) {
                        ForEach(Prefs.Content.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                    .onChange(of: content) { Prefs.shared.content = $0 }
                }
                hint("仅图标：只显示图标；实时数据：只显示数值；图标+数据：两者都显示。", singleLine: true)

                row("数据排列") {
                    Picker("", selection: $layout) {
                        ForEach(Prefs.Layout.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                    .onChange(of: layout) { Prefs.shared.layout = $0 }
                }
                hint(layout.hint)

                toggleRow("显示实时网速", isOn: $showSpeed) { Prefs.shared.showSpeed = $0 }
                hint("在右侧分两行显示上传与下载速率。")

                toggleRow("显示电池状态", isOn: $showBatteryState) { Prefs.shared.showBatteryState = $0 }
                hint("插头 = 已接电源，符号 = 充电 / 暂停 / 放电。")
                toggleRow("显示电池百分比", isOn: $showBatteryPercent) { Prefs.shared.showBatteryPercent = $0 }
                hint("在电池图标左侧显示电量；关掉电池状态后单独显示。")

                divider
                Text("状态数据")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ThemeColor.ink2)
                    .padding(.top, 4).padding(.bottom, 6)
                row("指标 1", dot: dotColor(slot1)) {
                    Picker("", selection: $slot1) {
                        ForEach(Prefs.Metric.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                    .onChange(of: slot1) { Prefs.shared.slot1 = $0 }
                }
                row("指标 2", dot: dotColor(slot2)) {
                    Picker("", selection: $slot2) {
                        ForEach(Prefs.Metric.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                    .onChange(of: slot2) { Prefs.shared.slot2 = $0 }
                }
                hint("最多选择两个状态指标。选择「不显示」可留空。")

                divider
                row("进程内存口径") {
                    Picker("", selection: $memMetric) {
                        ForEach(Prefs.MemMetric.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 130)
                    .onChange(of: memMetric) { Prefs.shared.memMetric = $0 }
                }
                hint(memMetric.hint)
                hint("共享页按进程各算一份，全机合计会大于系统已用内存。")
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ThemeColor.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ThemeColor.hairline, lineWidth: 1))

            versionRow
        }
        .padding(16)
        .frame(width: 420, alignment: .top)
        .background(ThemeColor.panel)
        // 用户可能去「系统设置 → 通用 → 登录项」里改过，回到本窗口时重新问一次系统，
        // 别让界面停在一个已经过时的值上。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginError = nil
            launchAtLogin = LoginItem.isEnabled
        }
    }

    // MARK: - 登录时启动

    private var loginRow: some View {
        HStack {
            Text("登录时启动").font(.system(size: 12)).foregroundStyle(ThemeColor.ink1)
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(
                get: { launchAtLogin },
                set: { on in
                    launchAtLogin = on
                    loginError = LoginItem.set(on)
                    // 注册失败就把界面回滚到系统的真实状态，
                    // 否则开关会停在一个系统里并不存在的“开”上。
                    if loginError != nil { launchAtLogin = LoginItem.isEnabled }
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var loginHint: some View {
        if let e = loginError {
            Text("设置失败：\(e)")
                .font(.system(size: 10))
                .foregroundStyle(ThemeColor.disk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
        } else if launchAtLogin && !LoginItem.runsFromApplications {
            // 登录项记的是“当前这个 bundle 的路径”。从 build/ 打开开关，登录时就从 build/ 起；
            // 之后装到 /Applications，那条记录指向的旧路径还在，看起来“能用”但跑的仍是旧副本。
            Text("当前从 build/ 运行，登录项指向该路径；装到「应用程序」后需要再开关一次。")
                .font(.system(size: 10))
                .foregroundStyle(ThemeColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
        } else {
            hint("登录后自动启动。也可在「系统设置 → 通用 → 登录项」里开关。")
        }
    }

    private var header: some View {
        Text("菜单栏")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ThemeColor.ink1)
            .padding(.bottom, 14)
    }

    /// 底部信息行：左「版本」、右版本号。取代原来那片被 `Spacer` 撑出来的空白。
    private var versionRow: some View {
        HStack(spacing: 8) {
            Text("版本")
            Spacer(minLength: 8)
            Text(Prefs.appVersion).monospacedDigit()
        }
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(ThemeColor.ink3)
        .padding(.top, 10)
    }

    private var divider: some View {
        Rectangle().fill(ThemeColor.hairline).frame(height: 1).padding(.vertical, 10)
    }

    /// 指标 → 身份色。与弹框同一套：CPU 青绿、GPU 蓝、内存紫、磁盘莓红。
    private func dotColor(_ m: Prefs.Metric) -> Color? {
        switch m {
        case .cpu: return ThemeColor.cpu
        case .gpu: return ThemeColor.gpu
        case .memory: return ThemeColor.mem
        case .disk: return ThemeColor.disk
        case .off: return nil
        }
    }

    private func row<C: View>(_ title: String, dot: Color? = nil,
                              @ViewBuilder control: () -> C) -> some View {
        HStack(alignment: .center, spacing: 8) {
            if let dot {
                Circle().fill(dot).frame(width: 8, height: 8)
            }
            Text(title).font(.system(size: 12)).foregroundStyle(ThemeColor.ink1)
            Spacer(minLength: 8)
            control()
        }
        .padding(.vertical, 5)
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>,
                           onChange: @escaping (Bool) -> Void) -> some View {
        HStack {
            Text(title).font(.system(size: 12)).foregroundStyle(ThemeColor.ink1)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn).labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: isOn.wrappedValue) { onChange($0) }
        }
        .padding(.vertical, 5)
        .disabled(!hasBattery && title.contains("电池"))
        .opacity(!hasBattery && title.contains("电池") ? 0.45 : 1)
    }

    /// 默认说明可换行；`singleLine` 用于显示方式那句——用户要求一行放完，
    /// 字号降半档 + `minimumScaleFactor` 兜底，避免超宽时被 SwiftUI 折成两行。
    @ViewBuilder
    private func hint(_ text: String, singleLine: Bool = false) -> some View {
        if singleLine {
            Text(text)
                .font(.system(size: 9.5))
                .foregroundStyle(ThemeColor.ink3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.bottom, 4)
        } else {
            Text(text)
                .font(.system(size: 10))
                .foregroundStyle(ThemeColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
        }
    }
}

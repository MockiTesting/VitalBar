// SPDX-License-Identifier: MIT

import AppKit
import Foundation

/// 偏好层。键名一律带 `vitalbar.` 前缀，绝不与其他应用的偏好域共用同名键。
final class Prefs {
    static let shared = Prefs()
    private let d = UserDefaults.standard

    enum Content: String, CaseIterable {
        case iconAndData, data, iconOnly
        var title: String {
            switch self {
            case .iconAndData: return "图标 + 数据"
            case .data: return "实时数据"
            case .iconOnly: return "仅图标"
            }
        }
    }

    enum Layout: String, CaseIterable {
        case sideBySide, stacked
        var title: String {
            switch self {
            case .sideBySide: return "分栏"
            case .stacked: return "堆叠"
            }
        }
        var hint: String {
            switch self {
            case .sideBySide: return "分栏：每个指标的标签在上、数值在下，两个指标左右并排。"
            case .stacked: return "堆叠：每个指标占一行，标签在左、数值在右。"
            }
        }
    }

    enum Look: Int, CaseIterable {
        case system, light, dark
        var title: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "浅色"
            case .dark: return "深色"
            }
        }
        /// `nil` = 跟随系统。**这是全应用唯一的外观到 NSAppearance 映射**：
        /// 设置窗口的标题栏、正文、弹框的材质都必须吃这一个值，否则三者会各走一套。
        var appearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    /// `off` 而不是 `none`：`none` 与 `Optional.none` 在 `switch` / `==` 里极易写错。
    enum Metric: String, CaseIterable {
        case cpu, memory, gpu, disk, off
        var title: String {
            switch self {
            case .cpu: return "CPU 使用率"
            case .memory: return "内存使用率"
            case .gpu: return "GPU 使用率"
            case .disk: return "磁盘占用"
            case .off: return "不显示"
            }
        }
        /// 菜单栏里的标签：列宽按字符数推导，`DISK` 是 4 字符，列宽会跟着放宽。
        var label: String {
            switch self {
            case .cpu: return "CPU"
            case .memory: return "MEM"
            case .gpu: return "GPU"
            case .disk: return "DISK"
            case .off: return ""
            }
        }
        var isOff: Bool { self == .off }
    }

    /// 进程内存口径。两者是**同一次** `proc_pid_rusage(RUSAGE_INFO_V4)` 返回结构里的
    /// 两个字段（`ri_phys_footprint` / `ri_resident_size`），换口径只换读哪个字段，
    /// 不增加 syscall——实测 565 进程一轮 0.85 ms → 0.84 ms，属噪声。
    enum MemMetric: String, CaseIterable {
        case footprint, rss
        var title: String {
            switch self {
            case .footprint: return "活动监视器口径"
            case .rss: return "常驻内存口径"
            }
        }
        /// 设置页的一句说明。两行以内，只讲「差在哪」和「读数往哪偏」。
        var hint: String {
            switch self {
            case .footprint:
                return "footprint：含压缩内存与映射文件，读数偏大，与活动监视器「内存」列接近。"
            case .rss:
                return "rss：只算此刻驻留的物理页，读数偏小，与 ps / top 的 RSS 一致。"
            }
        }
    }

    /// 设置页底部显示的版本号，取自 bundle，取不到时退回 0.0.1。
    static var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.1"
    }

    private func registerDefaults() {
        d.register(defaults: [
            Keys.content: Content.iconAndData.rawValue,
            Keys.layout: Layout.stacked.rawValue,
            Keys.showSpeed: true,
            Keys.showBatteryState: true,
            Keys.showBatteryPercent: true,
            Keys.look: Look.system.rawValue,
            Keys.slot1: Metric.cpu.rawValue,
            Keys.slot2: Metric.memory.rawValue,
            Keys.memMetric: MemMetric.footprint.rawValue,
        ])
    }

    enum Keys {
        static let content = "vitalbar.menubar.content"
        static let layout = "vitalbar.menubar.layout"
        static let showSpeed = "vitalbar.menubar.speed"
        static let showBatteryState = "vitalbar.menubar.batteryState"
        static let showBatteryPercent = "vitalbar.menubar.batteryPercent"
        static let look = "vitalbar.appearance"
        static let slot1 = "vitalbar.metric1"
        static let slot2 = "vitalbar.metric2"
        static let memMetric = "vitalbar.procMemMetric"
    }

    init() { registerDefaults() }

    var content: Content {
        get { Content(rawValue: d.string(forKey: Keys.content) ?? "") ?? .iconAndData }
        set { d.set(newValue.rawValue, forKey: Keys.content); notify() }
    }

    var layout: Layout {
        get { Layout(rawValue: d.string(forKey: Keys.layout) ?? "") ?? .stacked }
        set { d.set(newValue.rawValue, forKey: Keys.layout); notify() }
    }

    var showSpeed: Bool {
        get { d.bool(forKey: Keys.showSpeed) }
        set { d.set(newValue, forKey: Keys.showSpeed); notify() }
    }

    var showBatteryState: Bool {
        get { d.bool(forKey: Keys.showBatteryState) }
        set { d.set(newValue, forKey: Keys.showBatteryState); notify() }
    }

    var showBatteryPercent: Bool {
        get { d.bool(forKey: Keys.showBatteryPercent) }
        set { d.set(newValue, forKey: Keys.showBatteryPercent); notify() }
    }

    var look: Look {
        get { Look(rawValue: d.integer(forKey: Keys.look)) ?? .system }
        set { d.set(newValue.rawValue, forKey: Keys.look); notify() }
    }

    var slot1: Metric {
        get { Metric(rawValue: d.string(forKey: Keys.slot1) ?? "") ?? .cpu }
        set { d.set(newValue.rawValue, forKey: Keys.slot1); notify() }
    }

    var slot2: Metric {
        get { Metric(rawValue: d.string(forKey: Keys.slot2) ?? "") ?? .memory }
        set { d.set(newValue.rawValue, forKey: Keys.slot2); notify() }
    }

    var memMetric: MemMetric {
        get { MemMetric(rawValue: d.string(forKey: Keys.memMetric) ?? "") ?? .footprint }
        set { d.set(newValue.rawValue, forKey: Keys.memMetric); notify() }
    }

    static let changed = Notification.Name("vitalbar.prefsChanged")
    private func notify() { NotificationCenter.default.post(name: Prefs.changed, object: nil) }
}

// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

/// `VitalBar --dump <dir>`：把状态项与字形离屏渲染成 PNG，用于逐像素核对。
/// 交付包里保留这段，验收时替代截图目测（`scripts/verify.py` 会读这些图）。
///
/// `VitalBar --dump-ui <dir>`：把弹框按「五种功率形态 × 浅/深 × 1×/2×」离屏渲染。
/// 真机上五种电源状态无法同时复现（插电/放电由硬件决定），只有这一条路能一次看全。
enum RenderDump {
    static func run(dir: String) {
        let base = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        func save(_ img: NSImage, _ name: String, scale: CGFloat = 4) {
            let w = Int(img.size.width * scale), h = Int(img.size.height * scale)
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                             isPlanar: false, colorSpaceName: .deviceRGB,
                                             bytesPerRow: 0, bitsPerPixel: 0) else { return }
            rep.size = img.size          // 画布 4 倍，逻辑尺寸不变 → 文字按 4× 过采样绘制
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .none
            NSColor.white.setFill()
            NSRect(x: 0, y: 0, width: img.size.width, height: img.size.height).fill()
            img.draw(in: NSRect(origin: .zero, size: img.size))
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: base.appendingPathComponent(name))
            print("dump \(name) \(w)x\(h) imgW=\(String(format: "%.2f", img.size.width)) imgH=\(String(format: "%.2f", img.size.height))")
        }

        let p = Prefs.shared

        /// 指标槽按当前偏好取，与状态项走同一条路：选「不显示」的两行就少一行。
        func rows(cpu: Double, memory: Double, gpu: Double, disk: Double) -> [MenuBarRow] {
            [p.slot1, p.slot2].compactMap { m -> MenuBarRow? in
                guard !m.isOff else { return nil }
                let v: Double = {
                    switch m {
                    case .cpu: return cpu
                    case .memory: return memory
                    case .gpu: return gpu
                    case .disk: return disk
                    case .off: return 0
                    }
                }()
                return MenuBarRow(label: m.label, percent: v)
            }
        }

        let samples: [(String, MenuBarViewModel)] = [
            ("normal", MenuBarViewModel(rows: rows(cpu: 46, memory: 83, gpu: 21, disk: 86),
                                        up: 18 * 1024, down: 482 * 1024,
                                        battery: BatteryRead(percent: 80, external: true, charging: false,
                                                             full: false, watts: 0, installed: true),
                                        batteryState: .pause)),
            ("extremes", MenuBarViewModel(rows: rows(cpu: 100, memory: 9, gpu: 0, disk: 100),
                                          up: 0, down: 9.9 * 1024 * 1024,
                                          battery: BatteryRead(percent: 100, external: true, charging: false,
                                                               full: true, watts: 0, installed: true),
                                          batteryState: .pause)),
            ("charging", MenuBarViewModel(rows: rows(cpu: 9, memory: 8, gpu: 9, disk: 9),
                                          up: 999 * 1024, down: 999 * 1024,
                                          battery: BatteryRead(percent: 9, external: true, charging: true,
                                                               full: false, watts: 12, installed: true),
                                          batteryState: .charging)),
            ("unplugged", MenuBarViewModel(rows: rows(cpu: 46, memory: 83, gpu: 21, disk: 86),
                                           up: 7 * 1024, down: 12 * 1024,
                                           battery: BatteryRead(percent: 55, external: false, charging: false,
                                                                full: false, watts: -8, installed: true),
                                           batteryState: .unplugged)),
        ]

        for (name, m) in samples {
            let img = MenuBarRenderer.image(m, prefs: p, ink: .black)
            save(img, "bar-\(name).png")
            print("  width(\(name)) = \(MenuBarRenderer.width(m, prefs: p))")
        }
        print("  content=\(p.content.rawValue) layout=\(p.layout.rawValue) slots=\(p.slot1.rawValue)/\(p.slot2.rawValue)")
        for st in [BatteryState.charging, .pause, .discharging, .unplugged] {
            save(BatteryGlyph.image(state: st, color: .black), "glyph-\(st.rawValue).png", scale: 8)
        }
        print("done")
    }

    // MARK: - 弹框离屏渲染

    /// `--dump-ui`：五种电源形态 × 浅/深 × 1×/2×。
    ///
    /// 真机上「充电中 · 电池放电」几乎不会出现（`isCharging` 为真时电池几乎总在充），
    /// 但代码必须画对；只有离屏造样本能一次看全五态。
    static func dumpUI(dir: String) {
        _ = NSApplication.shared
        let base = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // `--disk-hex 0x4A6472,0x8FA6B8`：只影响本次离屏渲染，用来出一组磁盘配色的设计稿。
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--disk-hex"), i + 1 < args.count {
            let parts = args[i + 1].split(separator: ",")
            if parts.count == 2, let l = UInt32(parts[0], radix: 16), let d = UInt32(parts[1], radix: 16) {
                Theme.diskOverride = (light: l, dark: d)
                print("disk-hex light=\(String(format: "%06X", l)) dark=\(String(format: "%06X", d))")
            }
        }

        // `--warn-hex 0xC9A227,0xFFD24A` / `--warn-text-hex`：同上，只用于出配色设计稿。
        if let i = args.firstIndex(of: "--warn-hex"), i + 1 < args.count {
            let parts = args[i + 1].split(separator: ",")
            if parts.count == 2, let l = UInt32(parts[0], radix: 16), let d = UInt32(parts[1], radix: 16) {
                Theme.warnBarOverride = (light: l, dark: d)
                print("warn-hex light=\(String(format: "%06X", l)) dark=\(String(format: "%06X", d))")
            }
        }
        if let i = args.firstIndex(of: "--warn-text-hex"), i + 1 < args.count {
            let parts = args[i + 1].split(separator: ",")
            if parts.count == 2, let l = UInt32(parts[0], radix: 16), let d = UInt32(parts[1], radix: 16) {
                Theme.warnOverride = (light: l, dark: d)
                print("warn-text-hex light=\(String(format: "%06X", l)) dark=\(String(format: "%06X", d))")
            }
        }

        for (key, power) in powerSamples {
            for dark in [false, true] {
                render(PopupContainer { PopupView(snapshot: snapshot(power), infoOverride: mockInfo) },
                       scale: 1, dark: dark,
                       name: "popup-\(key)-\(dark ? "dark" : "light")-1x.png", base: base)
            }
        }
        for dark in [false, true] {
            render(PopupContainer { PopupView(snapshot: snapshot(powerSamples[0].1), infoOverride: mockInfo) },
                   scale: 2, dark: dark,
                   name: "popup-hold-\(dark ? "dark" : "light")-2x.png", base: base)
        }
        for dark in [false, true] {
            render(LevelLadder(), scale: 2, dark: dark,
                   name: "ladder-\(dark ? "dark" : "light")-2x.png", base: base)
        }
        render(SettingsView(), scale: 1, dark: false, name: "settings-light-1x.png", base: base)
        render(SettingsView(), scale: 1, dark: true, name: "settings-dark-1x.png", base: base)
        print("dump-ui done -> \(dir)")
    }

    /// 离屏图的头部一律用这组固定值：`--dump-ui` 的产物会进 README，
    /// 不能带上开发者本机的芯片、内存、系统版本与已开机时长——四者合起来足以指纹一台机器。
    private static let mockInfo = SystemInfo(
        chip: "Apple M1", memoryGB: "16.0 GB", osVersion: "macOS 14.5",
        uptime: "已运行 3天4小时",
        diskTotal: 228 * 1_073_741_824, diskFree: 31 * 1_073_741_824,
        loadAverage: 4.10, memoryTotalOverride: 16)

    private static func snapshot(_ power: PowerSample) -> Snapshot {
        var s = Snapshot()
        s.cpu = 39
        s.memory = 77
        s.gpu = 0
        s.disk = 87
        s.up = 18 * 1024
        s.down = 482 * 1024
        s.battery = BatteryRead(percent: 80, external: power.externalConnected,
                                charging: power.isCharging, full: false,
                                watts: power.batteryWatts ?? 0, installed: true)
        s.batteryState = power.isCharging ? .charging
            : (power.externalConnected ? .pause : .discharging)
        // pid 0 → ProcIcon 取不到图标，走字母兜底，渲染结果不依赖本机装了哪些 app。
        // v3.4.3：样本改成**归组后**的形状（同一 app 只一行、数值为合计），
        // 否则离屏图会和真机对不上——真机上一行浏览器已经是 21 个进程的合计。
        // 名称一律用中性占位：离屏图会进 README，不能暴露开发者本机装了哪些软件。
        s.processes = [
            ProcSample(pid: 0, name: "Web Browser", cpuPercent: 58.0, memoryBytes: 3_025_100_000, processCount: 21),
            ProcSample(pid: 0, name: "Work Suite", cpuPercent: 17.5, memoryBytes: 2_478_600_000, processCount: 31),
            ProcSample(pid: 0, name: "Chat App", cpuPercent: 57.4, memoryBytes: 1_676_000_000, processCount: 47),
            ProcSample(pid: 0, name: "Device Relay", cpuPercent: 13.7, memoryBytes: 554_800_000, processCount: 14),
            ProcSample(pid: 0, name: "Video Decoder", cpuPercent: 0.0, memoryBytes: 542_600_000),
        ]
        s.power = power
        return s
    }

    /// 五态样本。字段与 `PowerFlowDiagram.shape` 的判定一一对应：
    /// `externalConnected` / `isCharging` / `batteryWatts` 的符号决定排法。
    private static var powerSamples: [(String, PowerSample)] {
        func make(adapterV: Double?, adapterA: Double?, batteryV: Double?, batteryA: Double?,
                  adapter: Double?, battery: Double?, system: Double?,
                  charging: Bool, external: Bool, limit: Int?) -> PowerSample {
            var s = PowerSample()
            s.adapterVolts = adapterV
            s.adapterAmps = adapterA
            s.batteryVolts = batteryV
            s.batteryAmps = batteryA
            s.adapterWatts = adapter
            s.batteryWatts = battery
            s.systemWatts = system
            s.isCharging = charging
            s.externalConnected = external
            s.ratedWatts = 22
            s.adapterProtocol = external ? "USB-C PD" : nil
            s.profileVolts = external ? 20 : nil
            s.profileAmps = external ? 1.12 : nil
            s.externalLimit = limit
            s.externalLowerDelta = limit != nil ? 10 : nil
            s.percent = 80
            return s
        }
        return [
            ("hold", make(adapterV: 19.9, adapterA: 0.28, batteryV: 12.6, batteryA: 0,
                          adapter: 5.5, battery: 0.0, system: 5.5,
                          charging: false, external: true, limit: 80)),
            ("holdBatt", make(adapterV: 20.0, adapterA: 0.50, batteryV: 12.6, batteryA: -0.33,
                              adapter: 9.9, battery: -4.2, system: 14.1,
                              charging: false, external: true, limit: 80)),
            ("charge", make(adapterV: 20.0, adapterA: 0.71, batteryV: 12.9, batteryA: 0.64,
                            adapter: 14.2, battery: 8.2, system: 6.0,
                            charging: true, external: true, limit: nil)),
            ("chargeBatt", make(adapterV: 20.0, adapterA: 0.57, batteryV: 12.6, batteryA: -0.17,
                                adapter: 11.4, battery: -2.1, system: 13.5,
                                charging: true, external: true, limit: nil)),
            ("onBatt", make(adapterV: nil, adapterA: nil, batteryV: 12.6, batteryA: -0.92,
                            adapter: nil, battery: -11.4, system: 11.4,
                            charging: false, external: false, limit: nil)),
        ]
    }

    // MARK: - 行描边对比

    /// `--dump-outline`：只回答一个问题——进入 warn 时那圈 1 pt 描边调到多深才「框得住」。
    static func dumpOutline(dir: String) {
        _ = NSApplication.shared
        let base = URL(fileURLWithPath: dir)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        // 第一项是 nil → 走真实默认值。落地某个方案后，「默认」必须与对应变体
        // **逐像素相同**，否则说明改的不是真正在用的那条路径。
        let variants: [(String, (warn: Double, alert: Double)?)] = [
            ("default", nil),
            ("a-base", (0.30, 0.36)),
            ("b-warn45", (0.45, 0.36)), // v1.4 采用
            ("c-both", (0.45, 0.54)),   // warn / alert 同步提，保持两级差 9 pp
        ]
        for (name, v) in variants {
            Theme.rowOutlineOverride = v
            for dark in [false, true] {
                render(PopupContainer { PopupView(snapshot: outlineSnapshot(), infoOverride: mockInfo) },
                       scale: 2, dark: dark,
                       name: "outline-\(name)-\(dark ? "dark" : "light")-2x.png", base: base)
            }
        }
        Theme.rowOutlineOverride = nil
        print("dump-outline done -> \(dir)")
    }

    /// 四行刻意摆成 1 绿 2 黄 1 红：CPU 39 normal、GPU 66 warn、内存 92 alert、磁盘（本机真值）。
    /// 一张图里能同时看到 warning 与 alert 两档描边，不用来回比对两张图。
    /// 磁盘行的百分比取 `info.diskUsedPercent`（抓的是真实磁盘），离屏造不了，所以拿内存当 alert。
    private static func outlineSnapshot() -> Snapshot {
        var s = snapshot(powerSamples[0].1)
        s.cpu = 39     // normal
        s.gpu = 66     // warn（标准阈值 60 / 85）
        s.memory = 92  // alert
        return s
    }

    /// 把 SwiftUI 视图渲成 PNG。`scale` 决定像素密度，逻辑尺寸不变。
    private static func render<V: View>(_ v: V, scale: CGFloat, dark: Bool,
                                        name: String, base: URL) {
        let host = NSHostingView(rootView: v)
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(x: 0, y: 0, width: 400, height: 10)
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()

        let w = max(1, Int((size.width * scale).rounded()))
        let h = max(1, Int((size.height * scale).rounded()))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        // 垫一层「桌面」：毛玻璃要有东西可采样，否则整块是透明的
        (dark ? NSColor(srgbRed: 0.15, green: 0.16, blue: 0.18, alpha: 1)
              : NSColor(srgbRed: 0.90, green: 0.91, blue: 0.92, alpha: 1)).setFill()
        NSRect(origin: .zero, size: size).fill()
        host.cacheDisplay(in: host.bounds, to: rep)
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: base.appendingPathComponent(name))
        print("dump \(name) \(w)x\(h) pt=\(String(format: "%.1f", size.width))x\(String(format: "%.1f", size.height))")
    }
}

/// 电平条阶梯：同一组百分比在磁盘（15/18 段起变色）与 CPU（12/17 段）上的分色。
private struct LevelLadder: View {
    private let values: [Double] = [39, 62, 77, 87, 93, 100]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("CPU").font(.system(size: 9, design: .monospaced)).frame(width: 46, alignment: .leading)
                Text("磁盘").font(.system(size: 9, design: .monospaced)).frame(width: 46, alignment: .leading)
            }
            .foregroundStyle(ThemeColor.ink3)
            ForEach(values, id: \.self) { v in
                HStack(spacing: 9) {
                    LevelBar(percent: v, kind: .cpu)
                    LevelBar(percent: v, kind: .disk)
                    Text(String(format: "%.0f", v))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(ThemeColor.ink3)
                }
            }
        }
        .padding(12)
        .background(ThemeColor.card)
    }
}

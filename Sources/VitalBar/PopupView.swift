// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

/// 弹框的三个迷你图历史（各 30 点，1 Hz）。
/// v1.2 起四行指标不再画迷你图（规格里没有），但桥接层仍在维护，
/// 留着是为了不牵动 `PopupBridge` / `StatusItemController` 的签名。
struct HUDHistory {
    var cpu: [Double] = []
    var gpu: [Double] = []
    var mem: [Double] = []
}

/// 进程图标：按 PID 取所属 app 的图标，带缓存（每秒刷新不能每次都问 LaunchServices）。
/// 自身进程（VitalBar 那一行）直接读 bundle 里的 AppIcon.icns：NSRunningApplication.icon
/// 走的是 LaunchServices 图标缓存，替换 icns 后若缓存未刷新会显示旧图标；直读 bundle 不受影响。
enum ProcIcon {
    private static var cache: [Int32: NSImage] = [:]
    private static let selfPID = ProcessInfo.processInfo.processIdentifier
    static func image(pid: Int32) -> NSImage? {
        if let hit = cache[pid] { return hit }
        let icon: NSImage?
        if pid == selfPID {
            icon = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
                .flatMap { NSImage(contentsOf: $0) }
        } else {
            icon = NSRunningApplication(processIdentifier: pid)?.icon
        }
        guard let icon else { return nil }
        if cache.count > 240 { cache.removeAll() }
        cache[pid] = icon
        return icon
    }
}

/// 面板外框：毛玻璃 + 圆角 + 描边。弹框是透明无边框窗口，系统阴影会跟着这个形状走。
struct PopupContainer<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background {
                // 参考日历应用 那种玻璃：ultraThinMaterial 采样桌面，再压一层很薄的冷灰渐变。
                //
                // 深浅两档的不透明度不同，因为材质的**底色**不同：ultraThinMaterial 在深色下
                // 是「压暗的模糊」，背后是白窗口时它自己会被抬到中灰（实测 rgb 154,154,154）。
                // 0.82 的 wash 只盖住 18% 的它，整块面板于是被带到 `#373A47`、卡片 `#51545F`，
                // 9 pt 副标题 `#727C8A` 在上面只有 **1.7:1**——这就是「数值看不清」的真正原因，
                // 不是字号。深色提到 0.92 后 wash 基本定调（`#2C3039`），背后是什么都差不了几个点，
                // 玻璃的模糊仍在边缘可见。浅色材质本来就是亮底，0.82 不动。
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(ThemeColor.popupWash.opacity(scheme == .dark ? 0.92 : 0.82))
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    // 外圈刻意用中性灰：浅色主题下原来是深色 hairline，叠加系统
                    // 深色外观的材质边会变成一圈近黑的硬线（v3.2 实测 rgb 32,33,33）。
                    .strokeBorder(ThemeColor.popupOutline, lineWidth: 1)
            )
    }
}

// MARK: - 弹框（规格 v1.2）

/// 四行指标取代原来的 2×2 四张卡：每行 42 pt（padding 7 / 内容 26 / padding 7），
/// 栏宽 22 / flex / 79 / 56 全部整数。这样 334 宽的弹框能同时容下「图标 + 名称 + 副标题 +
/// 20 段电平 + 三位数读数」，而原来的卡片每张只有 26 pt 给数值和一条 4 pt 细条。
///
/// 身份与状态走两条通道：**图标恒为身份色**，warn / alert 只染数值、电平条尾段、
/// 1 pt 行描边。上一版把图标也按状态染色，内存 77% 与磁盘 87% 同时告警时两枚图标
/// 都变成琥珀——那才是「颜色太接近」的真实原因，不是色板。
struct PopupView: View {
    var snapshot: Snapshot
    var history = HUDHistory()
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}
    /// 离屏渲染用：固定头部系统信息，避免出图带本机芯片 / 内存 / 系统版本 / 已开机时长。
    var infoOverride: SystemInfo?

    /// 弹框固定宽度；开窗处也按这个数取，两边必须一致。
    static let width: CGFloat = 334
    private static let pagePad: CGFloat = 12
    private static let rowGap: CGFloat = 6
    private static let sectionGap: CGFloat = 8

    private enum SortKey { case memory, cpu }
    /// 默认按内存排：卡片是「主要进程」而不是「最忙进程」，
    /// 一个常驻 2 GB 但 CPU 为 0 的应用比一个 0.3% 的后台进程更值得看。
    @State private var sortKey: SortKey = .memory

    private var info: SystemInfo { infoOverride ?? SystemInfo.read() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Self.pagePad)
                .padding(.top, 9)
                .padding(.bottom, 8)
            metricRows
                .padding(.horizontal, Self.pagePad)
            powerCard
                .padding(.horizontal, Self.pagePad)
                .padding(.top, Self.sectionGap)
            processCard
                .padding(.horizontal, Self.pagePad)
                .padding(.top, Self.sectionGap)
            footer
                .padding(.top, Self.sectionGap)
        }
        .frame(width: Self.width)
    }

    // MARK: 顶部信息

    private var header: some View {
        let i = info
        return HStack(spacing: 5) {
            Chip(text: i.chip)
            Chip(text: i.memoryGB)
            Chip(text: i.osVersion)
            Spacer(minLength: 4)
            // 整条顶部唯一会变的数：比左边三枚胶囊高一级，但远不到四行读数的亮度。
            // 深浅两档都由 Theme.headerMeta 一处给，别再叠 opacity——0.86 那层在浅色下
            // 把这行压到 2.7:1，等于看不见。
            Text(i.uptime)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(ThemeColor.headerMeta)
                .lineLimit(1)
        }
    }

    // MARK: 四行指标

    private var metricRows: some View {
        // `infoOverride` 非 nil 表示这是离屏渲染：温度与内存压力也要固定，
        // 否则出图里会混进本机此刻的传感器读数与真实内存压力。
        let isPreview = infoOverride != nil
        let temps: (cpu: Double?, gpu: Double?) = isPreview ? (52, 41) : SensorReader.shared.temps()
        let pressure = isPreview ? 62 : MemoryPressure.percent()
        let usedGB = snapshot.memory / 100 * info.memoryTotal
        let diskUsedGB = max(0, info.diskTotalGB - info.diskFreeGB)

        return VStack(spacing: Self.rowGap) {
            row(.cpu,
                percent: snapshot.cpu,
                subtitle: tempLine(temps.cpu, trailing: String(format: "负载 %.2f", info.loadAverage)))

            row(.gpu,
                percent: snapshot.gpu,
                subtitle: tempLine(temps.gpu, trailing: info.chip))

            row(.mem,
                percent: snapshot.memory,
                // 整数 GB：这一列只有约 108 pt，`12.3/16 GB · 压力 62%` 在 16 GB 机器上会被截成
                // 「压力 6…」。去掉一位小数省 2 个字符，活动监视器本身也是整数显示。
                subtitle: String(format: "%.0f/%.0f GB · 压力 %d%%",
                                 usedGB, info.memoryTotal, pressure))

            row(.disk,
                percent: info.diskUsedPercent,
                subtitle: String(format: "已用 %.0f GB / %.0f GB", diskUsedGB, info.diskTotalGB))
        }
    }

    private func row(_ kind: MetricKind, percent: Double?, subtitle: String) -> some View {
        MetricRow(kind: kind, percent: percent, subtitle: subtitle)
    }

    /// 温度读不到就只留后半句，绝不把缺失写成 0°C。
    private func tempLine(_ t: Double?, trailing: String) -> String {
        guard let t, t > 0 else { return trailing }
        return String(format: "%.0f°C · %@", t, trailing)
    }

    // MARK: 功率分流

    private var powerCard: some View {
        let p = snapshot.power
        return GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    SectionLabel(text: "功率分流", glyph: .flow, color: ThemeColor.sysLoad)
                    Text(chargerSummary(p))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(ThemeColor.ink3)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let rated = p?.ratedWatts, rated > 0 {
                        Text(String(format: "%.0f W", rated))
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(ThemeColor.gold)
                            .fixedSize()
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(ThemeColor.gold.opacity(0.12)))
                    }
                }
                if let p, p.realtimeAvailable {
                    PowerFlowDiagram(sample: p)
                        .padding(.top, 6)
                    powerFacts(p)
                        .padding(.top, 5)
                } else if let p {
                    Text("这台 Mac 读不到实时功率")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(ThemeColor.ink3)
                        .lineLimit(1)
                        .padding(.top, 6)
                    powerFacts(p)
                        .padding(.top, 5)
                } else {
                    Text("正在读取功率…")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(ThemeColor.ink3)
                        .padding(.top, 6)
                }
            }
        }
    }

    /// 状态一行（左侧圆点 + 文案，右侧余量）+ 策略一行。两行分开，不挤在一句里。
    private func powerFacts(_ p: PowerSample) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Circle().fill(batteryTint(p)).frame(width: 5, height: 5)
                Text(stateLine(p))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(ThemeColor.ink2)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                if let head = p.headroomWatts {
                    Text(String(format: "余量 %.1f W", head))
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(ThemeColor.ink3)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            if let policy = policyLine(p) {
                Text(policy)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(ThemeColor.ink3)
                    .lineLimit(1)
            }
        }
    }

    /// "USB-C PD · 20.0 V · 2.87 A"——真正限制充电的是协商出来的上限，铭牌在右侧胶囊里。
    private func chargerSummary(_ p: PowerSample?) -> String {
        guard let p else { return "" }
        guard p.externalConnected else { return "未接电源" }
        var parts: [String] = []
        if let proto = p.adapterProtocol { parts.append(proto) }
        if let v = p.profileVolts, let a = p.profileAmps {
            parts.append(String(format: "%.1f V · %.2f A", v, a))
        }
        return parts.joined(separator: " · ")
    }

    /// 五种电源状态 → 文案。判定必须带 `batteryWatts` 的符号：
    /// 正值是充电（电池是负载），负值是放电（电池是电源）。
    private func stateLine(_ p: PowerSample) -> String {
        let watts = p.batteryWatts ?? 0
        switch p.chargeState {
        case .charging:
            if watts < -0.05 {
                return String(format: "充电器已接 · 电池反而放电 %.1f W", -watts)
            }
            return String(format: "充电中 · 电池 %.1f W", watts)
        case .holding:
            if watts < -0.05 {
                if let limit = p.externalLimit {
                    return String(format: "保持 %d%% · 电池补 %.1f W", limit, -watts)
                }
                return String(format: "插电不充电 · 电池补 %.1f W", -watts)
            }
            if p.externalLimit != nil, let percent = p.percent, percent >= 100 {
                return "已充满 · 电池静止"
            }
            if let limit = p.externalLimit {
                return String(format: "插电保持 %d%% · 电池静止", limit)
            }
            return "插电不充电 · 电池静止"
        case .unplugged:
            return String(format: "电池供电 · 电池 %.1f W", watts)
        case .unknown:
            return "电源状态不可用"
        }
    }

    /// 只有本机存在充电策略且插着电时才显示——那是唯一需要解释「为什么没在充电」的场景。
    private func policyLine(_ p: PowerSample) -> String? {
        guard p.externalConnected, !p.isCharging, let limit = p.externalLimit else { return nil }
        if let delta = p.externalLowerDelta, delta > 0, limit - delta > 0 {
            return String(format: "外部策略：上限 %d%%，保持 %d–%d%%", limit, limit - delta, limit)
        }
        return String(format: "外部策略：上限 %d%%", limit)
    }

    /// 圆点是「电池此刻有没有电流」的指示，用电池色而不是 ok 绿：
    /// 功率区里已经有三种角色色，再加一个第四色只会让人重新学一遍。
    private func batteryTint(_ p: PowerSample) -> Color {
        abs(p.batteryWatts ?? 0) > 0.05 ? ThemeColor.batt : ThemeColor.ink3
    }

    // MARK: 主要进程

    private var sortedProcesses: [ProcSample] {
        let list = snapshot.processes
        switch sortKey {
        case .cpu: return list.sorted { $0.cpuPercent > $1.cpuPercent }
        case .memory: return list.sorted { $0.memoryBytes > $1.memoryBytes }
        }
    }

    private var processCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                SectionLabel(text: "主要进程", glyph: nil, color: ThemeColor.ink2)
                Spacer(minLength: 4)
                // 列名就是排序开关：点哪列按哪列降序，宽度与下面的数值格一致，
                // 所以数字始终维持同一条右边缘。
                sortHeader("内存", .memory, width: 58)
                sortHeader("%CPU", .cpu, width: 40)
            }
            .padding(.bottom, 3)

            if snapshot.processes.isEmpty {
                Text("采集中…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ThemeColor.ink3)
                    .padding(.vertical, 8)
            } else {
                ForEach(Array(sortedProcesses.prefix(5).enumerated()), id: \.offset) { i, p in
                    row(p, first: i == 0)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ThemeColor.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(ThemeColor.hairline, lineWidth: 1))
    }

    private func sortHeader(_ title: String, _ key: SortKey, width: CGFloat) -> some View {
        let active = sortKey == key
        return Button { sortKey = key } label: {
            Text(title)
                .font(.system(size: 9.5, weight: active ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(active ? ThemeColor.ink1 : ThemeColor.ink3)
                .frame(width: width, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(key == .memory ? "按内存排序（\(Prefs.shared.memMetric.title)）" : "按\(title)排序")
    }

    private func row(_ p: ProcSample, first: Bool) -> some View {
        HStack(spacing: 7) {
            if let icon = ProcIcon.image(pid: p.pid) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ThemeColor.chip)
                    .frame(width: 16, height: 16)
                    .overlay(
                        Text(String(p.name.prefix(1)).uppercased())
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(ThemeColor.ink2)
                    )
            }
            Text(p.name)
                .font(.system(size: 10.5))
                .foregroundStyle(ThemeColor.ink2)
                .lineLimit(1)
                // 同一 app 的 helper 已合并成一行；进程数只放在 tooltip，不占列宽。
                .help(p.processCount > 1 ? "\(p.name)：\(p.processCount) 个进程合计" : p.name)
            Spacer(minLength: 4)
            Text(memText(p))
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(ThemeColor.ink3)
                .frame(width: 58, alignment: .trailing)
            Text(String(format: "%.1f", p.cpuPercent))
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                // 9.5 pt 上 #C07919 只有 3.3:1，所以这里用 warn-ink 那一档。
                .foregroundStyle(p.cpuPercent > 30 ? ThemeColor.warnInk : ThemeColor.ink2)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 3.5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if !first {
                Rectangle().fill(ThemeColor.hairline).frame(height: 1)
            }
        }
    }

    /// 与 参考格式化逻辑 同格式：1024 进制、非整数单位保留 1 位小数
    /// （<10 时 2 位），这样 `118.9 MB` / `333.5 MB` 这类读数能逐项对照。
    private func memText(_ p: ProcSample) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = p.memoryBytes
        var i = 0
        while v >= 1024, i < units.count - 1 { v /= 1024; i += 1 }
        let s = i == 0 ? "\(Int(v))" : String(format: v < 10 ? "%.2f" : "%.1f", v)
        return "\(s) \(units[i])"
    }

    // MARK: 底部（参考日历应用 式：一条分割线 + 左右两个纯文字按钮）

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(ThemeColor.hairline)
                .frame(height: 1)
            HStack(spacing: 8) {
                FooterButton(title: "设置", icon: "gearshape", action: onSettings)
                Spacer(minLength: 0)
                FooterButton(title: "退出", icon: "power", action: onQuit)
            }
            .padding(.horizontal, Self.pagePad)
            .frame(height: 38)
        }
    }
}

// MARK: - 指标行

/// 一行四栏：22 图标 / 名称+副标题 / 79 电平条 / 56 读数。
///
/// 高 42 = 上下各 7 的 padding + 26 的正文块（11.5 标题 + 2.5 间距 + 9 副标题），
/// 多出来的 2 pt 正好被 1 pt 描边吃掉，所以四行摞起来的节拍是 48。
private struct MetricRow: View {
    let kind: MetricKind
    let percent: Double?
    let subtitle: String

    private var value: Double { percent ?? 0 }

    private var level: Theme.Level {
        guard percent != nil else { return .normal }
        return Theme.level(for: value, kind.thresholds)
    }

    private var valueColor: Color {
        switch level {
        case .normal: return ThemeColor.ink1
        case .warn: return ThemeColor.warn
        case .alert: return ThemeColor.alert
        }
    }

    private var glyph: GlyphKind {
        switch kind {
        case .cpu: return .cpu
        case .gpu: return .gpu
        case .mem: return .mem
        case .disk: return .disk
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            // 身份色恒定：跨过阈值时只有数值、尾段与描边变色，图标不动。
            GlyphView(kind: glyph, size: 22, color: ThemeColor.identity(kind))

            VStack(alignment: .leading, spacing: 2.5) {
                Text(kind.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(ThemeColor.ink1)
                // 9 而不是 9.5：磁盘那句「已用 201 GB / 228 GB」在 9.5 上会被截成「228…」，
                // 而这一列只有约 108 pt 的弹性宽度。可读性靠墨色（ink3 提亮）解决，不靠字号。
                Text(subtitle)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(ThemeColor.ink3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.88)
                    .allowsTightening(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            LevelBar(percent: value, kind: kind)

            HStack(alignment: .firstTextBaseline, spacing: 1.5) {
                Text(percent == nil ? "—" : String(format: "%.0f", value))
                    .font(.system(size: 19, weight: .semibold, design: .monospaced))
                    .tracking(-0.4)
                    .foregroundStyle(valueColor)
                Text("%")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(ThemeColor.ink3)
            }
            .frame(width: 56, alignment: .trailing)
            .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .frame(height: 42)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(ThemeColor.card))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(ThemeColor.hairline, lineWidth: 1))
        .overlay {
            // 状态描边是「再叠一层 30% / 36% 的色」，不是把 rule 混色：
            // 动态色在 init 时混会按当时的外观求值，叠层则由环境在绘制时解析。
            if level != .normal {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(ThemeColor.levelColor(level)
                                    .opacity(level == .alert ? Theme.rowOutlineAlert : Theme.rowOutlineWarn),
                                  lineWidth: 1)
            }
        }
        // 全文唯一的动画：跨阈值时 0.18 s 颜色过渡。数值本身不补间。
        .animation(.easeOut(duration: 0.18), value: level)
    }
}

/// 底部按钮：默认只有灰字和一个齿轮/电源符号，hover 时出现一块很浅的圆角底。
private struct FooterButton: View {
    var title: String
    var icon: String
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .regular))
                Text(title)
                    .font(.system(size: 10.5))
            }
            .foregroundStyle(hover ? ThemeColor.ink1 : ThemeColor.ink2)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hover ? ThemeColor.cardAlt : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hover = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(title)
    }
}

// MARK: - 功率流向图

/// 「电从哪来、到哪去」。先定角色，再定位置：**源在左，汇在右**。
///
/// 适配器和电池都可能是源（放电时电池是源，充电时电池是汇），系统负载永远是汇。
/// 五种电源状态因此只落在三种排法上（1-1 / 2-1 / 1-2），不必为每种状态单独画一张图。
///
/// 判定必须带符号：`batteryWatts > 0` 是充电（电池是负载），`< 0` 是放电（电池是电源）。
/// 旧实现只看「充电中 + 电池有电流」，于是「充电中 · 电池放电」会被画成
/// 适配器往电池里灌，方向正好反了——插着充电器、峰值负载超过适配器能力时真会发生。
private struct PowerFlowDiagram: View {
    let sample: PowerSample

    private enum M {
        static let width: CGFloat = 290      // 弹框 334 − 页边 24 − 卡片内边 20
        static let col: CGFloat = 112        // 左列宽 = 节点宽
        static let rightX: CGFloat = 178     // 右列起点，跨距 66
        static let nodeH: CGFloat = 48
        static let single: CGFloat = 56
        static let stacked: CGFloat = 104
    }

    private enum Role { case adapter, battery, system }

    private struct Node {
        var role: Role
        var title: String
        var watts: Double?
        var detail: String
        var y: CGFloat
        var x: CGFloat = 0
    }

    private struct Ribbon {
        var y1: CGFloat
        var y2: CGFloat
        var watts: Double
        /// 带子取**源头**的颜色：充电时电池是汇，那条带仍然是适配器的金。
        var role: Role
    }

    private enum Shape {
        case single(Role)    // 1 源 1 汇（含电池供电）
        case twoOne          // 2 源 1 汇
        case oneTwo          // 1 源 2 汇
    }

    private var batteryWatts: Double { sample.batteryWatts ?? 0 }
    private var adapterWatts: Double { sample.externalConnected ? (sample.adapterWatts ?? 0) : 0 }

    private var shape: Shape {
        guard sample.externalConnected else { return .single(.battery) }
        if sample.isCharging {
            if batteryWatts > 0.05 { return .oneTwo }
            if batteryWatts < -0.05 { return .twoOne }
            return .single(.adapter)
        }
        if batteryWatts < -0.05 { return .twoOne }
        return .single(.adapter)
    }

    var body: some View {
        let plan = makePlan()
        return ZStack(alignment: .topLeading) {
            ForEach(plan.ribbons.indices, id: \.self) { i in
                ribbon(plan.ribbons[i], height: plan.height)
            }
            ForEach(plan.nodes.indices, id: \.self) { i in
                node(plan.nodes[i])
                    .offset(x: plan.nodes[i].x, y: plan.nodes[i].y)
            }
        }
        .frame(width: M.width, height: plan.height, alignment: .topLeading)
    }

    // MARK: 排法

    private func makePlan() -> (height: CGFloat, nodes: [Node], ribbons: [Ribbon]) {
        switch shape {
        case .single(let key):
            let y = (M.single - M.nodeH) / 2
            let left = key == .battery ? batteryNode(x: 0, y: y) : adapterNode(x: 0, y: y)
            let watts = key == .battery ? abs(batteryWatts) : adapterWatts
            return (M.single,
                    [left, systemNode(x: M.rightX, y: y)],
                    [Ribbon(y1: 28, y2: 28, watts: watts, role: key)])

        case .twoOne:
            // 适配器在上、电池在下，两股都汇到右侧居中的系统负载。
            return (M.stacked,
                    [adapterNode(x: 0, y: 0),
                     batteryNode(x: 0, y: 56),
                     systemNode(x: M.rightX, y: 28)],
                    [Ribbon(y1: 24, y2: 44, watts: adapterWatts, role: .adapter),
                     Ribbon(y1: 80, y2: 60, watts: abs(batteryWatts), role: .battery)])

        case .oneTwo:
            // 适配器居中偏下，右上系统、右下电池——与规格表逐项一致。
            return (M.stacked,
                    [adapterNode(x: 0, y: 28),
                     systemNode(x: M.rightX, y: 0),
                     batteryNode(x: M.rightX, y: 56)],
                    [Ribbon(y1: 44, y2: 24, watts: sample.systemWatts ?? 0, role: .adapter),
                     Ribbon(y1: 60, y2: 80, watts: abs(batteryWatts), role: .adapter)])
        }
    }

    // MARK: 节点

    private func node(_ n: Node) -> some View {
        let tint = color(n.role)
        let on = (n.watts ?? 0) > 0.05
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tint.opacity(0.10))
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(tint.opacity(on ? 0.40 : 0.20), lineWidth: 1)
            Text(n.title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(ThemeColor.ink3)
                .offset(x: 9, y: 6)
            HStack(alignment: .firstTextBaseline, spacing: 2.5) {
                Text(n.watts.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .tracking(-0.2)
                    .foregroundStyle(on ? ThemeColor.ink1 : ThemeColor.ink2)
                if n.watts != nil {
                    Text("W")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(ThemeColor.ink3)
                }
            }
            .offset(x: 9, y: 18)
            Text(n.detail.isEmpty ? " " : n.detail)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(ThemeColor.ink3)
                .lineLimit(1)
                .offset(x: 9, y: 33)
        }
        .frame(width: M.col, height: M.nodeH, alignment: .topLeading)
    }

    private func adapterNode(x: CGFloat, y: CGFloat) -> Node {
        Node(role: .adapter, title: "适配器", watts: adapterWatts,
             detail: voltsAmps(sample.adapterVolts, sample.adapterAmps), y: y, x: x)
    }

    private func batteryNode(x: CGFloat, y: CGFloat) -> Node {
        let charging = batteryWatts > 0.05
        return Node(role: .battery,
                    title: charging ? "电池充电" : "电池输出",
                    watts: charging ? batteryWatts : abs(batteryWatts),
                    detail: voltsAmps(sample.batteryVolts, sample.batteryAmps), y: y, x: x)
    }

    private func systemNode(x: CGFloat, y: CGFloat) -> Node {
        Node(role: .system, title: "系统负载", watts: sample.systemWatts,
             detail: loadDetail, y: y, x: x)
    }

    // MARK: 带子

    private func ribbon(_ r: Ribbon, height: CGFloat) -> some View {
        let tint = color(r.role)
        let ghost = r.watts <= 0.05
        let mid = (M.col + M.rightX) / 2
        // 终点比右列左沿退 2 pt：箭头若压在方框描边上会被那条 1 pt 边吃掉。
        let endX = M.rightX - 2
        let w = ghost ? 1 : bandWidth(r.watts)
        // 箭头随带宽缩放。固定 4.5×5.6 的箭头在 7.6 pt 宽的带子上会被带子整个盖住，
        // 1× 屏实拍就是这样——方向完全读不出来；带宽 11 W 时箭头要 18×12 才看得见。
        let headLen = ghost ? 0 : min(12, max(7, w * 1.2))
        let headHalf = ghost ? 0 : max(3.5, w * 0.75 + 1.5)

        let band = Path { p in
            p.move(to: CGPoint(x: M.col, y: r.y1))
            p.addCurve(to: CGPoint(x: endX - headLen * 0.55, y: r.y2),
                       control1: CGPoint(x: mid, y: r.y1),
                       control2: CGPoint(x: mid, y: r.y2))
        }
        // 箭头恒指向右（汇在右），三角与带子同色、同透明度。
        let head = Path { p in
            p.move(to: CGPoint(x: endX - headLen, y: r.y2 - headHalf))
            p.addLine(to: CGPoint(x: endX, y: r.y2))
            p.addLine(to: CGPoint(x: endX - headLen, y: r.y2 + headHalf))
            p.closeSubpath()
        }

        return ZStack(alignment: .topLeading) {
            if ghost {
                // 零瓦也留位：虚线占着那条道，切状态时带子不会整体跳一下。
                band.stroke(tint.opacity(0.30),
                            style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 4]))
            } else {
                band.stroke(tint.opacity(0.85),
                            style: StrokeStyle(lineWidth: w, lineCap: .round))
                head.fill(tint.opacity(0.85))
            }
        }
        .frame(width: M.width, height: height, alignment: .topLeading)
    }

    /// 开根号而不是线性：0.4 W 的涓流要在 20 W 的负载旁边仍然看得见，粗端也不能吞掉整段跨距。
    private func bandWidth(_ watts: Double) -> CGFloat {
        min(9, max(2, sqrt(max(watts, 0) / 20) * 10))
    }

    private func color(_ r: Role) -> Color {
        switch r {
        case .adapter: return ThemeColor.gold
        case .battery: return ThemeColor.batt
        case .system: return ThemeColor.sysLoad
        }
    }

    /// 「负载 49%」= 系统功耗 ÷ 适配器额定功率（10.8 W ÷ 22 W）。
    private var loadDetail: String {
        guard let f = sample.loadFraction else { return "" }
        return String(format: "负载 %.0f%%", f * 100)
    }

    private func voltsAmps(_ v: Double?, _ a: Double?) -> String {
        guard let v, let a else { return "" }
        return String(format: "%.1f V · %.2f A", v, a)
    }
}

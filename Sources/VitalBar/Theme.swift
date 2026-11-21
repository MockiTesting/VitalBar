// SPDX-License-Identifier: MIT

import AppKit

/// 配色令牌（规格 v1.6）。
///
/// 三层语义，任何一处的颜色只能属于其中一层：
///
/// 1. **身份**（谁）——CPU / GPU / 内存 / 磁盘各一个色，**永远不被状态覆盖**。
///    四点在色环上隔开：172° / 215° / 264° / 322°（HSL），最近的一对隔 58°；
///    按 OKLab 记磁盘是 346°，正好落在内存 298° 与朱红 28° 的正中。
/// 2. **状态**（多糟）——warn 琥珀、alert 朱红。只染数值、电平条尾段、1 pt 行描边。
///    这两个色靠**明度**分开（L 63.7 / 44.7），不是靠色相：3 pt 宽的色块上
///    只差色相会并成一条橙。
/// 3. **面与墨**（层级）——panel / card / rule / track + ink1..3。
///
/// 全部是动态色，浅/深两套由**窗口所属的 NSAppearance** 决定——外观覆盖只作用于
/// 弹框与设置窗口，菜单栏状态项永远跟随系统（见 StatusItemController 的注释）。
enum Theme {
    private static func dyn(_ dark: UInt32, _ darkA: CGFloat,
                            _ light: UInt32, _ lightA: CGFloat) -> NSColor {
        NSColor(name: nil) { app in
            let isDark = app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                           green: CGFloat((hex >> 8) & 0xff) / 255,
                           blue: CGFloat(hex & 0xff) / 255,
                           alpha: isDark ? darkA : lightA)
        }
    }

    private static func solid(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255,
                green: CGFloat((v >> 8) & 0xff) / 255,
                blue: CGFloat(v & 0xff) / 255,
                alpha: 1)
    }

    // MARK: 墨

    /// 数值、标题。对比度 ≥ 9:1（深色卡片 `#3B3F48` 上 9.4:1）。
    static let ink1 = dyn(0xF5F7FB, 1.00, 0x0F1318, 1.00)
    /// 正文、进程名。深色 `#B6C0CE`（卡片上 6.0:1）——v1.5 从 `#A6B0BF` 提上来：
    /// 玻璃会把背后的亮内容带进面板，实测卡片是 `#51545F` 而不是规格假定的 `#161B22`，
    /// 旧值在那上面只有 3.4:1。
    static let ink2 = dyn(0xB6C0CE, 1.00, 0x525B68, 1.00)
    /// 副标题、单位。深色 `#A8B2C1`（卡片 `#404550` 上 **4.4:1**）：旧值 `#727C8A` 在
    /// 真机卡片上只有 **1.7:1**——9 pt 等宽字直接糊成一片。这是「最低一档」能到的上限：
    /// 再亮就和 ink2 分不出来了。
    static let ink3 = dyn(0xA8B2C1, 1.00, 0x7E8794, 1.00)

    // MARK: 顶部信息条
    //
    // 顶部只有两类信息，重要性都低于四行读数，但彼此有高低：
    // 左边三枚胶囊（芯片 / 内存 / 系统版本）是**静态**元数据，看一次就不会再看；
    // 右边运行时长是唯一会变的，重要性略高。
    // 深浅两套都要让「胶囊 < 时长 < 读数」这个顺序成立，且胶囊不许压到读不下去。

    /// 胶囊文字。深色从 ink2 `#A6B0BF`（对胶囊底 7.2:1）降到 `#8B95A5`（5.2:1）：
    /// 原来的亮度和进程名同档，10 pt 的中等字重在顶部一直抢眼；压完顶部退成一条注释，
    /// 仍高于 AA 的 4.5:1。浅色维持 ink2 `#525B68`（对胶囊底 7.0:1）——浅色下它本来
    /// 就比读数暗一档，不存在抢眼问题。
    static let headerChip = dyn(0x8B95A5, 1.00, 0x525B68, 1.00)
    /// 运行时长。深色 `#A0AAB8`（对玻璃 6.6:1）比胶囊高一档，但不碰 ink1 的读数亮度。
    /// 浅色从「ink3 @0.86」换成 `#6B7482`：原来合成出来只有 2.7:1，10 pt 灰字几乎读不出。
    /// 浅色刻意**不**把这行做得比胶囊更重（那要接近 ink1，会跟读数抢），只把它从
    /// 「看不见」提到 4.4:1——层级仍是胶囊略强，这是胶囊在浅色下不动的代价。
    static let headerMeta = dyn(0xA0AAB8, 1.00, 0x6B7482, 1.00)

    // 旧名保留（设置页与历史调用点仍在用），语义与 ink1..3 完全相同。
    static let text1 = ink1
    static let text2 = ink2
    static let text3 = ink3

    // MARK: 面

    /// 卡片填充：浅色是白 80% 的纸片；深色是白 **6%** 的提亮。
    /// 深色从 11.5% 一路降到 6%：11.5% 把卡片抬到 `#51545F`，比面板亮一大截，
    /// 上面的 9 pt 灰字全被冲掉；6% 之后卡片 `#404550`，与面板只差一档——
    /// 仍读作「浮起的一层」，但不再吃掉墨色。
    static let card     = dyn(0xE8ECF7, 0.060, 0xFFFFFF, 0.80)
    static let cardAlt  = dyn(0xE8ECF7, 0.150, 0x1B1F2A, 0.06)
    static let hairline = dyn(0xE8ECF7, 0.190, 0x1B1F2A, 0.13)
    static let hairlineStrong = dyn(0xE8ECF7, 0.260, 0x1B1F2A, 0.22)
    /// 弹框最外圈：浅色下用明确的中性灰（不是深色 hairline），避免系统深色 +
    /// app 浅色时材质边缘合成出近黑的硬线；灰色比几乎不可见的白线更有边界感。
    static let popupOutline = dyn(0xE8ECF7, 0.24, 0x8A8F9A, 0.42)
    static let track    = dyn(0xE8ECF7, 0.170, 0x1B1F2A, 0.10)
    /// 顶部胶囊、进程字母块的底。
    ///
    /// **半透明叠层，不再是不透明色块**。原来深色写死 `#1D232C`、浅色 `#EDF0F5`，
    /// 而它们底下的东西有两种：弹框顶部是玻璃面板，进程字母块压在卡片上。
    /// 面板亮度本身由玻璃采到的桌面决定（见 v1.6），固定的 `#1D232C` 于是会随壁纸
    /// 在「略亮的小块」和「略暗的凹槽」之间来回翻——同一枚胶囊，换张壁纸就变了个意思。
    /// 改成叠层后由底决定，面板上、卡片上都是同一档。
    ///
    /// 深浅两套都往**暗**走（不透明度高的墨叠），所以两边的胶囊都是一枚「凹槽」，
    /// 与运行时长共用同一套层级。试过深色改成 9% 白（macOS 那种「填充往上加白」）：
    /// 胶囊会被抬到 `#4B4E59`，比卡片还亮，而胶囊上那档灰字 `#8B95A5` 只有 2.74:1；
    /// 要读就得把字提到 `#B6C0CE`，那又比运行时长 `#A0AAB8` 更亮，把 v1.5 定的
    /// 「胶囊 < 时长 < 读数」整个反过来。**这枚胶囊的文字是按深底选的，底就不能往亮走。**
    /// 实测量：深色 52% 墨给出 `#212631`（文字 5.01:1，胶囊/面板 1.31）；
    /// 浅色 5.5% 墨给出 `#F1F3F4`，与旧值 `#F1F3F7` 差 1–3 个色阶，肉眼看不出。
    static let chip     = dyn(0x0B0F16, 0.520, 0x1B1F2A, 0.055)

    /// 没有毛玻璃时的兜底底色，也是设置窗口的底（设置页不是玻璃，用不透明面板色）。
    static let window = dyn(0x0F1319, 1.0, 0xFAFBFD, 1.0)
    static let panel  = dyn(0x0F1319, 1.0, 0xFAFBFD, 1.0)

    // MARK: 身份色（谁）
    //
    // 缩到 22 pt 时**色相比明度更抗压缩**，所以四个色沿色环铺开而不是沿亮阶。
    // 深色下统一提亮一档，并保持同样的 71° 最小间隔。

    static let cpuColor  = dyn(0x45D2BD, 1, 0x0C8A79, 1)   // 172° 青绿
    static let gpuColor  = dyn(0x7FB2FF, 1, 0x2A6ACC, 1)   // 215° 蓝
    static let memColor  = dyn(0xA394FF, 1, 0x7440C0, 1)   // 264° 紫
    /// 335° → **346° 品红**。上一版是 358° 的玫红，铺到 3 pt 电平条上会跟状态色糊成一条。
    /// 往品红推 12° 并提彩度之后：条上金黄 `#C9A227` **31.3**、朱红 15.5、内存 15.7；
    /// 深色 29.8 / 13.9 / 15.9。条上的三档（品红 → 金 → 朱红）现在是这里差得最开的一组，
    /// 最弱的一对（对朱红）根本不相邻，它们之间始终隔着三段金黄。
    /// 没有进一步压深：压到 L48 能把金黄差拉到 40+，但朱红会掉到 9 以下，
    /// 两条暗色端头反而认不出来。
    /// 设计稿实验用：`--disk-hex 0x4A6472,0x8FA6B8`（浅,深）。只由 RenderDump 设置，
    /// 正常启动永远是 nil，不影响真机。改色只需重跑一次 dump，不用动这一行。
    nonisolated(unsafe) static var diskOverride: (light: UInt32, dark: UInt32)?

    private static let diskDefault = dyn(0xEE74B8, 1, 0xB33584, 1)

    static var diskColor: NSColor {
        if let o = diskOverride { return dyn(o.dark, 1, o.light, 1) }
        return diskDefault
    }

    // MARK: 状态色（多糟）
    //
    // 浅色 warn L 63.7 / alert L 44.7（差 19.0），深色 85.7 / 69.2（差 16.5）。
    // **改这两个色时先看 L 差是否还 ≥ 16**，再看色相——上一版 L 只差 4.3，
    // 缩到 3 pt 就并成一条橙。

    nonisolated(unsafe) static var warnOverride: (light: UInt32, dark: UInt32)?
    nonisolated(unsafe) static var warnBarOverride: (light: UInt32, dark: UInt32)?

    private static let warnDefault = dyn(0xFFC470, 1, 0xC07919, 1)
    private static let warnBarDefault = dyn(0xFFD24A, 1, 0xC9A227, 1)

    static var warn: NSColor {
        if let o = warnOverride { return dyn(o.dark, 1, o.light, 1) }
        return warnDefault
    }
    /// 小字号专用的琥珀：`#C07919` 在 9.5 pt 上只有 3.3:1，进程列表里的 %CPU 用这个。
    static let warnInk = dyn(0xFFC470, 1, 0x9B5C13, 1)
    /// **电平条里的琥珀段**用的更亮更黄一档（浅色 `#C9A227`）。
    ///
    /// 文字要对比卡片（≥3:1），色块要对比**左右邻居**——两个目标不同，取值本来就该不同。
    /// 演变：`#C07919`（对品红 ΔE 22.8）→ `#D18F1D`（27.5）→ `#C9A227`（**31.3**）。
    /// 为什么是「更黄」而不是「更深」：ΔE 里明度占大头，品红 okL 54.1，黄必须比它**亮**
    /// 才分得开；试过压深的 `#B08C18`，对品红只有 26.9，比 `#D18F1D` 还差。
    /// 色相从 okH 74° 推到 90°（再往上就是 CPU 的青绿 172°），红味被抽掉，
    /// 1× 屏上品红→金是两条硬边，不再读成「一根正在变暖的条」。
    /// 代价：对比卡片 2.56 → 2.25，与未点亮 track 仍差 25.0（> 18），不会糊进空槽。
    /// 深色 `#FFD24A`：在 `#161B22` 上对比 12.0，对品红 29.8。
    static var warnBar: NSColor {
        if let o = warnBarOverride { return dyn(o.dark, 1, o.light, 1) }
        return warnBarDefault
    }
    static let alert  = dyn(0xFF5F4B, 1, 0x9A1D18, 1)

    /// 进入 warn / alert 时，行外那圈 1 pt 描边的不透明度（叠在 hairline 上）。
    ///
    /// 描边不做成「把 hairline 混色」：动态色在 init 时混会按当时的外观求值，
    /// 叠一层则由环境在绘制时解析，切换深浅色不会残留旧值。
    /// 数值越大，这一行越「被框住」。v1.4 把 warn 从 0.30 提到 0.45：
    /// 30% 时混出的边色与灰 hairline 只差 ΔE 7.4，等于还是灰的；45% 才成一条金边
    /// （ΔE 13.0 / 深色 31.7）。alert 仍是 0.36——朱红本身明度低，提亮会把浅色下的
    /// 红框推成粉色（`#C88582`），红框不需要再靠不透明度补存在感。
    /// `--dump-outline 0.45,0.54` 只由 RenderDump 设置，正常启动是 nil。
    nonisolated(unsafe) static var rowOutlineOverride: (warn: Double, alert: Double)?

    static var rowOutlineWarn: Double { rowOutlineOverride?.warn ?? 0.45 }
    static var rowOutlineAlert: Double { rowOutlineOverride?.alert ?? 0.36 }

    // MARK: 功率三角形色
    //
    // 适配器的金与 warn 只差 ΔEok 8.1，允许共存的前提是**功率区没有阈值语义**：
    // 它是 112×48 的填充方块，与 3 pt 刻度段在面积、形状、位置上都不同。
    // 如果哪天功率区要加告警色，金必须换成中性。

    static let gold    = dyn(0xE7AE58, 1, 0x9A6A14, 1)   // 适配器
    static let batt    = dyn(0x79C98B, 1, 0x2E7D46, 1)   // 电池
    static let sysLoad = dyn(0xAEB6C2, 1, 0x5C636E, 1)   // 系统负载：耗电方，不该有彩度

    // 旧令牌：仍在别处引用（MeterBar 默认色、空闲点、accent），保留但不再新增用法。
    static let accent = solid(0x6FA8FF)
    static let ok     = dyn(0x4ECB8E, 1, 0x0F7C60, 1)
    static let idle   = solid(0x8E8E93)
    static let blue   = solid(0x5B9BE8)

    // MARK: 分级

    /// 指标的状态分级：只有跨阈值才允许染数值。
    enum Level: Equatable { case normal, warn, alert }

    /// 每个指标一套阈值——**琥珀 / 朱红在电平条上的起点由它算，不写死段号**。
    /// 60/85 → 第 12/17 段；磁盘 75/90 → 第 15/18 段。旧版把 12/17 写死给所有行，
    /// 87% 的磁盘因此提前橙了 5 段。
    struct Thresholds: Equatable {
        var warn: Double
        var alert: Double

        static let standard = Thresholds(warn: 60, alert: 85)
        static let disk = Thresholds(warn: 75, alert: 90)

        /// 20 段、每段 5%，0 基下标。
        var warnSegment: Int { Int((warn / 5).rounded(.down)) }
        var alertSegment: Int { Int((alert / 5).rounded(.down)) }
    }

    static func level(for percent: Double, _ t: Thresholds = .standard) -> Level {
        if percent >= t.alert { return .alert }
        if percent >= t.warn { return .warn }
        return .normal
    }

    /// normal 不再返回强调色：数值平时就是 ink1，颜色只在跨阈值后出现。
    static func levelColor(_ l: Level) -> NSColor {
        switch l {
        case .normal: return ink1
        case .warn: return warn
        case .alert: return alert
        }
    }

    /// 21 pt 图标用的身份色。
    static func identity(_ m: MetricKind) -> NSColor {
        switch m {
        case .cpu: return cpuColor
        case .gpu: return gpuColor
        case .mem: return memColor
        case .disk: return diskColor
        }
    }

    // MARK: 字体

    static func ui(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func mono(_ size: CGFloat, _ weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}

/// 四行指标的身份。放在 Theme 旁边是因为「哪个指标是什么色」属于配色，不属于视图。
enum MetricKind: String, CaseIterable {
    case cpu, gpu, mem, disk

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .gpu: return "GPU"
        case .mem: return "内存"
        case .disk: return "磁盘"
        }
    }

    var thresholds: Theme.Thresholds {
        self == .disk ? .disk : .standard
    }
}

// MARK: - SwiftUI 侧的同名令牌

import SwiftUI

/// SwiftUI 不接受 NSColor 当 ShapeStyle，颜色在这里转一次。
enum ThemeColor {
    static let ink1 = Color(nsColor: Theme.ink1)
    static let ink2 = Color(nsColor: Theme.ink2)
    static let ink3 = Color(nsColor: Theme.ink3)
    static let headerChip = Color(nsColor: Theme.headerChip)
    static let headerMeta = Color(nsColor: Theme.headerMeta)
    static let text1 = Color(nsColor: Theme.text1)
    static let text2 = Color(nsColor: Theme.text2)
    static let text3 = Color(nsColor: Theme.text3)
    static let card = Color(nsColor: Theme.card)
    static let cardAlt = Color(nsColor: Theme.cardAlt)
    static let hairline = Color(nsColor: Theme.hairline)
    static let hairlineStrong = Color(nsColor: Theme.hairlineStrong)
    static let popupOutline = Color(nsColor: Theme.popupOutline)
    static let track = Color(nsColor: Theme.track)
    static let chip = Color(nsColor: Theme.chip)
    static let window = Color(nsColor: Theme.window)
    static let panel = Color(nsColor: Theme.panel)
    static let accent = Color(nsColor: Theme.accent)
    static let ok = Color(nsColor: Theme.ok)
    static let idle = Color(nsColor: Theme.idle)
    static let blue = Color(nsColor: Theme.blue)

    static let cpu = Color(nsColor: Theme.cpuColor)
    static let gpu = Color(nsColor: Theme.gpuColor)
    static let mem = Color(nsColor: Theme.memColor)
    static let disk = Color(nsColor: Theme.diskColor)

    static var warn: Color { Color(nsColor: Theme.warn) }
    static let warnInk = Color(nsColor: Theme.warnInk)
    static var warnBar: Color { Color(nsColor: Theme.warnBar) }
    static let alert = Color(nsColor: Theme.alert)
    static let gold = Color(nsColor: Theme.gold)
    static let batt = Color(nsColor: Theme.batt)
    static let sysLoad = Color(nsColor: Theme.sysLoad)

    static func identity(_ m: MetricKind) -> Color { Color(nsColor: Theme.identity(m)) }

    static func levelColor(_ l: Theme.Level) -> Color {
        switch l {
        case .normal: return ink1
        case .warn: return warn
        case .alert: return alert
        }
    }

    static func level(_ l: Theme.Level) -> Color { levelColor(l) }

    /// 弹框底色：毛玻璃之上再压一层很薄的冷灰渐变，深浅两套都保持「玻璃」而不是「实心卡」。
    /// 三个停点取自面板背景的实测采样。
    static var popupWash: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color(nsColor: NSColor(name: nil) { ap in
                    ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                        ? NSColor(srgbRed: 0x28 / 255.0, green: 0x2C / 255.0, blue: 0x38 / 255.0, alpha: 1)
                        : NSColor(srgbRed: 0xFB / 255.0, green: 0xFC / 255.0, blue: 0xFE / 255.0, alpha: 1)
                }), location: 0.0),
                .init(color: Color(nsColor: NSColor(name: nil) { ap in
                    ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                        ? NSColor(srgbRed: 0x22 / 255.0, green: 0x25 / 255.0, blue: 0x2F / 255.0, alpha: 1)
                        : NSColor(srgbRed: 0xF6 / 255.0, green: 0xF8 / 255.0, blue: 0xFC / 255.0, alpha: 1)
                }), location: 0.45),
                .init(color: Color(nsColor: NSColor(name: nil) { ap in
                    ap.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                        ? NSColor(srgbRed: 0x19 / 255.0, green: 0x1B / 255.0, blue: 0x22 / 255.0, alpha: 1)
                        : NSColor(srgbRed: 0xF1 / 255.0, green: 0xF3 / 255.0, blue: 0xF9 / 255.0, alpha: 1)
                }), location: 1.0),
            ],
            startPoint: .top, endPoint: .bottom)
    }
}

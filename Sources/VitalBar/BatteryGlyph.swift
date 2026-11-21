// SPDX-License-Identifier: MIT

import AppKit

/// 电池状态四态。判定顺序见 BatteryMonitor。
enum BatteryState: String {
    case charging, pause, discharging, unplugged
}

/// 外壳画法。v3.4 起做成可切换参数，供「实心壳线 / 半透明细线」A/B 决策；
/// 用户已拍板选 B，**线上默认 `.translucent`**（55% 半透明 1 pt 细线，贴近实拍的 ~0.50 白）。
/// 要回退到 v3.0–v3.3 的纯色实心环，把 `image(...)` 的默认 `style` 改回 `.solid` 即可。
enum BatteryShellStyle {
    /// 纯色 1 pt 实心壳线：外圆角矩形填充 → 内圆角矩形 `.clear` 挖空。
    case solid
    /// 半透明细线：同一几何、1 pt 描边、alpha 0.55（**v3.4 定稿选定**）。
    /// 1 pt 描边仍落在整数像素网格上，所以只是变淡、不会回到 v2.9 那种半像素灰边；
    /// 贴近实拍的 ~50% 白壳线。插头、状态符、正极凸点仍保持 100% 实心。
    case translucent
}

/// 四角倒脚半径（外 / 内）。内外圆心重合、半径差恒等于壳厚 1 pt，四边与四角厚度均匀。
struct BatteryCorners {
    var outer: CGFloat
    var inner: CGFloat
    /// v3.4：把系统菜单栏实拍的倒脚换算到我们的「1 pt 实心环」上。
    /// 实拍壳高 12 px、角部过渡 2.5–3 px（r/h≈0.25）；描边图标的等效中线半径比
    /// 实心环小 0.5 pt，故外 3 / 内 2（等效中线 2.5，r/h≈0.21）最贴近观感。
    static let menuBarRounded = BatteryCorners(outer: 3, inner: 2)
    /// v3.2–v3.3 的旧值，留作对照 / 一键回退。
    static let legacy = BatteryCorners(outer: 2, inner: 1)
}

/// 菜单栏电池字形：25 × 14 pt，三元素 = 外壳 + 左侧插头 + 右侧状态符。
///
/// v3.0 把描边改成整数坐标实心填充、高度从 13 改成偶数 14，解决 1× 屏整圈灰边。
/// v3.1 把外壳圆角放大到 4 pt、插头改成完全落在壳内的圆润一体形状。
/// v3.2 按 24× 放大的系统电池图标 24× 放大与 1× 菜单栏窗口实测回退造型：
/// - **插头穿出壳边**：两根针向上穿出壳顶、细尾柱向下穿出壳底，壳的顶/底边
///   在插头贯穿处挖断口（系统图标就是这样断开的，不是闭合环里套一个插头）；
/// - **四角圆角调小**：外 4 → 2 pt、内 3 → 1 pt；
/// - **未接电时的短横居中**：lx=9 → 8，x=8..14 中心正好落在内腔中心 11；
/// - 所有直边仍是整数坐标实心填充，AA 只落在圆角与杯身上，1× 屏不产生半像素灰边。
///
/// v3.3 按用户给的 系统图标参考图（28×16）做「协调性」修正：
/// - 插头改成**上宽下窄、斜边连续收腰的一体酒杯形**，再顺成细柄；
/// - 暂停/充电状态符由粗直角矩形改成细长圆角条，与圆润插头同一套语言；
/// - 顶边断口扩到杯口宽度（x=4..12），底边断口仍只让开细柄。
///
/// v3.4 两处参数化（本轮「示意图 + 由用户决策」）：
/// - **倒脚弧度**：系统电池状态项窗口逐像素量得壳高 12 px、角部过渡 2.5–3 px，
///   而我们 r=2/1 的实心环在 1× 上读起来几乎是直角。默认改为 `menuBarRounded`（外 3 / 内 2）。
///   断口从 x=4 起，半径 3 只覆盖 x=0..3，四个圆角仍完整可见；
/// - **壳线风格**：新增 `BatteryShellStyle`，二者共用同一套几何与同一份插头/状态符，
///   只有外壳画法不同。A/B 示意图交用户决策后**选定 B（55% 半透明 1 pt 细线）**，
///   倒脚同时定稿为 `r = 3 / 2`；`image(...)` 默认 `style` 与 `defaultCorners` 即当前线上值。
enum BatteryGlyph {
    static let size = NSSize(width: 25, height: 14)

    // 外壳：外沿 22×12，内腔挖 20×10 → 四周各 1 pt 硬边
    private static let shellOuter = CGRect(x: 0, y: 1, width: 22, height: 12)
    private static let shellInner = CGRect(x: 1, y: 2, width: 20, height: 10)
    private static let electrode = CGRect(x: 23, y: 5, width: 2, height: 4)

    /// 默认倒脚：系统电池实拍匹配值。改这一行即可整体切换 / 回退。
    static let defaultCorners = BatteryCorners.menuBarRounded

    /// 壳线与正极凸点的墨量（v1.2）。插头、状态符始终 100%——
    /// 三者的轻重关系是「插头最实、壳线次之、正极再次之」，不是四个一样重。
    static let shellAlpha: CGFloat = 0.68
    static let electrodeAlpha: CGFloat = 0.85

    /// 插头贯穿处挖的断口：顶边让开两根针与杯口，底边只让开尾柱本身。
    /// 挖在「画完外壳之后、画插头之前」，所以断口里的插头后画时是完整的。
    private static let topNotch = CGRect(x: 4, y: 0, width: 8, height: 4)
    private static let bottomNotch = CGRect(x: 7, y: 11, width: 2, height: 3)

    /// 插头是**圆弧杯口 + 二次曲线收腰的一体高脚杯**，不是「药丸 + 独立细棍」拼接，
    /// 也不是折角漏斗。20× 放大对照 系统电池图标：杯口是圆润的（近似心形），
    /// 两侧以曲线连续收到 2 pt 细柄，细柄穿出壳底；两根 1 pt 针从杯口上缘穿出壳顶。
    ///
    /// 刻意拆成多个独立路径分别填充：曲线轮廓与矩形/椭圆的绕向不一定一致，
    /// 塞进同一条 CGPath 用非零环绕合并会出现互相抵消的洞。同色逐次填充结果等价，
    /// 且直边（针、细柄、外壳）仍是整数像素硬边，AA 只落在杯口与收腰的曲线上。
    private static func plugPaths() -> [CGPath] {
        var out: [CGPath] = []
        for x in [CGFloat(5), 10] {
            let p = CGMutablePath()
            p.addRect(CGRect(x: x, y: 0, width: 1, height: 4))              // 两根针
            out.append(p)
        }
        let cup = CGMutablePath()
        cup.addEllipse(in: CGRect(x: 4, y: 3, width: 8, height: 4))          // 圆润杯口
        out.append(cup)

        let waist = CGMutablePath()
        waist.move(to: CGPoint(x: 4.5, y: 5))
        waist.addQuadCurve(to: CGPoint(x: 7, y: 10), control: CGPoint(x: 4.5, y: 9))
        waist.addLine(to: CGPoint(x: 9, y: 10))
        waist.addQuadCurve(to: CGPoint(x: 11.5, y: 5), control: CGPoint(x: 11.5, y: 9))
        waist.closeSubpath()
        out.append(waist)

        let stem = CGMutablePath()
        stem.addRoundedRect(in: CGRect(x: 7, y: 8, width: 2, height: 6),
                            cornerWidth: 1, cornerHeight: 1)                 // 细柄穿出壳底
        out.append(stem)
        return out
    }

    /// 状态符：加号=充电、双竖条=暂停、短横=接电放电 / 未接电。
    /// 未接电时没有插头，短横独占内腔并精确居中；其余状态的状态符在右段 x=14..20，
    /// 与插头（最右到 x=12）留 2 pt 硬空白，不会糊在一起。
    ///
    /// v1.2 把竖臂从 8 收到 **6 pt**（y=4..10）：8 pt 的加号上下顶到内腔沿（内腔 2..12），
    /// 和穿出壳顶的插头针挤在一起；收到 6 pt 后加号与插头之间重新有了空气。
    /// 暂停双条同步收到 6 pt，两种状态符仍然同高。
    private static func symbolPath(_ s: BatteryState) -> CGPath {
        let p = CGMutablePath()
        let lx: CGFloat = (s == .unplugged) ? 8 : 14          // 居中 / 右段
        switch s {
        case .charging:
            p.addRoundedRect(in: CGRect(x: lx, y: 6, width: 6, height: 2),
                             cornerWidth: 1, cornerHeight: 1)
            p.addRoundedRect(in: CGRect(x: lx + 2, y: 4, width: 2, height: 6),
                             cornerWidth: 1, cornerHeight: 1)
        case .pause:
            // 系统电池图标 的暂停是两根细长圆角竖条，不是粗直角方块；端点 1 pt 圆角。
            p.addRoundedRect(in: CGRect(x: lx, y: 4, width: 2, height: 6),
                             cornerWidth: 1, cornerHeight: 1)
            p.addRoundedRect(in: CGRect(x: lx + 4, y: 4, width: 2, height: 6),
                             cornerWidth: 1, cornerHeight: 1)
        case .discharging, .unplugged:
            p.addRect(CGRect(x: lx, y: 6, width: 6, height: 2))
        }
        return p
    }

    /// 几何用「左上原点」，因此先翻转 y 轴——不翻转的话整枚插头会上下颠倒。
    ///
    /// - `style` / `corners` 都带默认值；线上调用 `image(state:color:)` 走 v3.4 定稿值
    ///   （半透明细线 + r=3/2）。对比示意图显式传参逐项渲染 A/B 与不同倒脚，
    ///   保证图与运行时是**同一份几何**。
    /// - 回退壳线：把下面 `style` 的默认值改回 `.solid`；回退倒脚：`defaultCorners = .legacy`。
    static func image(state: BatteryState, color: NSColor,
                      style: BatteryShellStyle = .translucent,
                      corners: BatteryCorners = defaultCorners) -> NSImage {
        let img = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setShouldAntialias(true)
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
            let ink = color.cgColor
            ctx.setFillColor(ink)

            // 1) 外壳：两种画法共用同一外沿 / 半径 / 壳厚，只有「实填 vs 半透明描边」不同
            let outerPath = CGPath(roundedRect: shellOuter,
                                   cornerWidth: corners.outer, cornerHeight: corners.outer,
                                   transform: nil)
            switch style {
            case .solid:
                // 实心圆角外框 → 挖空圆角内腔（比 stroke 的半像素灰边硬得多）
                ctx.addPath(outerPath)
                ctx.fillPath()
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.addPath(CGPath(roundedRect: shellInner,
                                   cornerWidth: corners.inner, cornerHeight: corners.inner,
                                   transform: nil))
                ctx.fillPath()
                ctx.restoreGState()
            case .translucent:
                // 1 pt 描边：路径内缩半线宽，描边外沿正好落回 shellOuter 的整数边界。
                // 因此只是「变淡」，不会像 v2.9 的半像素描边那样整圈发灰。
                //
                // v1.2：alpha 0.55 → **0.68**。55% 在浅色菜单栏上是一层灰，
                // 和 100% 的插头并排放着像两件东西；0.68 与正极凸点（0.85）同一重量。
                ctx.saveGState()
                ctx.setAlpha(shellAlpha)
                ctx.setStrokeColor(ink)
                ctx.setLineWidth(1)
                ctx.addPath(CGPath(roundedRect: shellOuter.insetBy(dx: 0.5, dy: 0.5),
                                   cornerWidth: max(0.5, corners.outer - 0.5),
                                   cornerHeight: max(0.5, corners.outer - 0.5),
                                   transform: nil))
                ctx.strokePath()
                ctx.restoreGState()
            }

            // 2) 顶/底边在插头贯穿处断开：系统与 系统电池图标 都是这个形状
            if state != .unplugged {
                ctx.saveGState()
                ctx.setBlendMode(.clear)
                ctx.addRect(topNotch)
                ctx.addRect(bottomNotch)
                ctx.fillPath()
                ctx.restoreGState()
            }

            // 3) 右侧正极凸点（圆角小方块），与壳线同一重量（0.85）
            ctx.saveGState()
            ctx.setAlpha(electrodeAlpha)
            ctx.setFillColor(ink)
            ctx.addPath(CGPath(roundedRect: electrode, cornerWidth: 1, cornerHeight: 1, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()

            // 4) 插头与状态符（在断口之后画，保证穿出的针与尾柱完整）
            if state != .unplugged {
                for path in plugPaths() { ctx.addPath(path); ctx.fillPath() }
            }
            ctx.addPath(symbolPath(state))
            ctx.fillPath()
            return true
        }
        img.isTemplate = false      // 已用文字同色重绘，再标 template 会被系统二次着色
        return img
    }
}

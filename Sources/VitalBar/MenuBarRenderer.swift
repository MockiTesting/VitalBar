// SPDX-License-Identifier: MIT

import AppKit
import CoreText

struct MenuBarRow {
    var label: String
    var percent: Double?
}

struct MenuBarViewModel {
    var rows: [MenuBarRow]
    var up: Double
    var down: Double
    var battery: BatteryRead
    var batteryState: BatteryState
}

/// 菜单栏状态项渲染（规格 v1.2）。
///
/// 一条状态项由四段可选块拼成，**从左到右**：
///
///     [应用图标] [指标块] [网速块] [电池块]
///
/// 每块的宽度只由「显示方式 / 数据排列 / 三个开关 / 选了哪两个指标」决定，
/// **绝不由当前数值决定**：`9` → `100`、`9 KB/s` → `999 KB/s` 都只是列内重新对齐。
///
/// v1.2 只改字阶与墨量，**不加任何新元素**（没有刻度、不画应用图标）：
///
/// | 元素 | 旧 | 新 | 墨量 |
/// |---|---|---|---|
/// | 标签 | 10 semibold | **9 semibold** | 66% |
/// | 数值 | 10 medium | **11 medium** | 100% |
/// | 单位 % | 10（与数值同串） | **8.5 regular** | 58% |
/// | 网速 | 10 medium | 10 medium | 90% |
/// | 电池 % | 11 semibold | 11 semibold | 100% |
///
/// 百分比拆成「数值 + 单位」两次绘制是这一版的关键：它让 `%` 不再和数字抢宽度，
/// 也让 `9` 与 `100` 的变化只影响数字本身。24 pt 高的地方放第三种信息（刻度）
/// 只会让人先决定看哪个——刻度的信息量在弹框的 20 段里已经完整表达。
///
/// v2.9 清晰度修复保留：不手工造 2× NSBitmapImageRep，改用 `NSImage(drawingHandler:)`
/// 让 AppKit 按目标窗口的 scale 出图；所有列宽与落笔点取整。
enum MenuBarRenderer {
    // MARK: 字体
    //
    // 标签压小一档（索引不是内容），数值放大一档（菜单栏唯一真正要读的东西），
    // 单位再淡一档（重复信息）。三者同一基线。
    static let labelFontSize: CGFloat = 9
    static let valueFontSize: CGFloat = 11
    static let unitFontSize: CGFloat = 8.5
    static let speedFontSize: CGFloat = 10
    static let battFontSize: CGFloat = 11

    static let labelFont = NSFont.monospacedSystemFont(ofSize: labelFontSize, weight: .semibold)
    static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: valueFontSize, weight: .medium)
    static let unitFont = NSFont.monospacedSystemFont(ofSize: unitFontSize, weight: .regular)
    static let speedFont = NSFont.monospacedDigitSystemFont(ofSize: speedFontSize, weight: .medium)
    static let battFont = NSFont.monospacedDigitSystemFont(ofSize: battFontSize, weight: .semibold)

    // MARK: 墨量
    //
    // 三档亮度本身就是层级：标签 66%、单位 58%、数值 100%。
    // **不要**给标签加 tracking——1× 屏上会落到半像素，整枚标签发灰。

    static let labelInk: CGFloat = 0.66
    static let valueInk: CGFloat = 1.00
    static let unitInk: CGFloat = 0.58
    static let speedInk: CGFloat = 0.90

    /// 数值用「等宽数字」字体量 ch，标签用等宽字体量 chLabel——两者字符宽度并不相同，
    /// 混用会让 `CPU` / `MEM` 的预留宽度偏掉。
    static let ch: CGFloat = ("0" as NSString).size(withAttributes: [.font: valueFont]).width
    static let chLabel: CGFloat = ("0" as NSString).size(withAttributes: [.font: labelFont]).width
    static let chUnit: CGFloat = ("0" as NSString).size(withAttributes: [.font: unitFont]).width
    static let chSpeed: CGFloat = ("0" as NSString).size(withAttributes: [.font: speedFont]).width

    // MARK: 几何常量（一律整数点，保证 1× 像素对齐）

    static let height: CGFloat = 24             // 与 NSStatusBarButton 同高，免缩放
    /// 两行文字当作一个紧凑块整体居中；11 与 9 的 cap 差变大，行距 2 会贴，故 3。
    static let lineGap: CGFloat = 3
    /// 系统给每个 NSStatusItem 固定加了左右各 8 pt inset（实测窗口宽 = image 宽 + 16）。
    static let leftPad: CGFloat = 1
    static let rightPad: CGFloat = 1
    /// 每块都变宽了，块与块要多一口气。
    static let blockGap: CGFloat = 5
    /// 菜单栏图标按 SVG 的设计占位（24 画布里图形占 19.9）取 18 pt。
    static let iconSize: CGFloat = 18

    static let labelGap: CGFloat = 3
    /// 并排两列时 11 pt 的数字更宽，列距 5 → 6。
    static let columnGap: CGFloat = 6
    static let speedGap: CGFloat = 2

    /// 箭头列单独给 8 pt 整数宽：原来用 1ch 时箭头中心落在半像素，
    /// 1× 屏上竖线被 AA 摊到两列像素，看着发虚。
    static let wArrow: CGFloat = 8
    static let wSpeedNum: CGFloat = (3 * chSpeed).rounded(.up)
    static let wSpeedUnit: CGFloat = (4 * chUnit).rounded(.up)
    /// 3 位数字 ×6.6 + `%` ×5.1 ≈ 24.9，取整留 1 pt 空气。旧值按 4 个数字宽算成 27。
    static let wPct: CGFloat = 26
    /// 电池那格比指标多 2 pt：`100%` 是 5 个字形（25.9），26 只剩 0.1 pt 余量，
    /// 1× 屏上 `%` 会和电池壳贴在一起。固定 28，数字变化时仍然不推挤。
    static let wBattPct: CGFloat = 28
    static let battGap: CGFloat = 3

    // MARK: 排版计划

    /// 宽度与绘制的唯一真源：`image()` 完全按这里算出的 x 落笔。
    struct Plan {
        var showsIcon = false
        var rows: [MenuBarRow] = []
        var layout: Prefs.Layout = .stacked
        var showsSpeed = false
        var batteryPercent: Int?
        var batteryState: BatteryState?

        var iconW: CGFloat = 0
        var metricsW: CGFloat = 0
        var columnW: CGFloat = 0
        var speedW: CGFloat = 0
        var battW: CGFloat = 0

        /// 两行都占满才上下分带；只有一行时垂直居中，避免半截留白。
        var twoRows: Bool {
            if layout == .sideBySide && !rows.isEmpty { return true }
            if showsSpeed { return true }
            return rows.count > 1
        }

        var width: CGFloat {
            var blocks: [CGFloat] = []
            if iconW > 0 { blocks.append(iconW) }
            if metricsW > 0 { blocks.append(metricsW) }
            if speedW > 0 { blocks.append(speedW) }
            if battW > 0 { blocks.append(battW) }
            let gaps = blockGap * CGFloat(max(0, blocks.count - 1))
            // 整数宽度：statusItem.length 与 button 宽度一致，image 才不会被拉伸半个像素。
            return (leftPad + rightPad + blocks.reduce(0, +) + gaps).rounded(.up)
        }
    }

    static func plan(_ m: MenuBarViewModel, prefs: Prefs) -> Plan {
        var p = Plan()
        p.layout = prefs.layout
        p.showsIcon = prefs.content != .data
        let showsData = prefs.content != .iconOnly
        p.rows = showsData ? Array(m.rows.prefix(2)) : []
        p.showsSpeed = prefs.showSpeed && showsData
        // 「仅图标」= 状态项里除了 VitalBar 图标什么都不留，电池块也一起收掉；
        // 两个电池开关只在有数据的两种模式下生效。
        p.batteryPercent = (showsData && prefs.showBatteryPercent) ? m.battery.percent : nil
        p.batteryState = (showsData && prefs.showBatteryState) ? m.batteryState : nil

        if p.showsIcon { p.iconW = iconSize }

        if !p.rows.isEmpty {
            let labelChars = p.rows.map { CGFloat($0.label.count) }.max() ?? 0
            let labelW = (labelChars * chLabel).rounded(.up)
            if p.layout == .sideBySide {
                p.columnW = max(labelW, wPct)
                let n = CGFloat(p.rows.count)
                p.metricsW = p.columnW * n + columnGap * (n - 1)
            } else {
                // 上下排列：标签 + 3 + 26。`MEM` 时 = 17 + 3 + 26 = 46
                p.metricsW = labelW + labelGap + wPct
            }
        }

        if p.showsSpeed {
            p.speedW = wArrow + speedGap + wSpeedNum + speedGap + wSpeedUnit
        }

        if p.batteryPercent != nil { p.battW += wBattPct }
        if p.batteryState != nil {
            p.battW += (p.batteryPercent != nil ? battGap : 0) + BatteryGlyph.size.width.rounded(.up)
        }
        return p
    }

    static func width(_ m: MenuBarViewModel, prefs: Prefs) -> CGFloat {
        plan(m, prefs: prefs).width
    }

    // MARK: 速率格式化

    static func rate(_ bytesPerSec: Double) -> (num: String, unit: String) {
        let kb = max(0, bytesPerSec) / 1024
        if kb < 999.5 { return (String(format: "%.0f", kb), "KB/s") }
        let mb = kb / 1024
        if mb < 9.95 { return (String(format: "%.1f", mb), "MB/s") }
        if mb < 999.5 { return (String(format: "%.0f", mb), "MB/s") }
        return (String(format: "%.1f", mb / 1024), "GB/s")
    }

    /// 数值与单位分两次画，`%` 才不会是数字的一部分。
    static func percentParts(_ p: Double?) -> (num: String, unit: String) {
        guard let p, p.isFinite else { return ("—", "") }
        return ("\(Int(p.rounded()))", "%")
    }

    // MARK: 绘制

    /// 参考做法：`NSImage(drawingHandler:)` 不预设位图倍率，AppKit 在真正绘制时
    /// 按 `NSStatusBarButton.window.backingScaleFactor` 决定缓存 rep 的像素密度。
    /// 固定 2× rep 在 1× 屏上会被下采样，是 v2.8 及以前文字发虚的主因。
    static func image(_ m: MenuBarViewModel, prefs: Prefs, ink: NSColor) -> NSImage {
        let p = plan(m, prefs: prefs)
        let w = max(p.width, 1)
        let h = height
        let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setShouldAntialias(true)
            ctx.setAllowsAntialiasing(true)
            // bitmap/透明上下文里 LCD 子像素 AA 不可用，但开启字体平滑仍会启用
            // hinting 与灰度平滑，小字的竖笔画不会再被摊成一片灰。
            ctx.setAllowsFontSmoothing(true)
            ctx.setShouldSmoothFonts(true)

            var x = leftPad
            var drewBlock = false

            if p.iconW > 0 {
                if let icon = MenubarIcon.tinted(ink, size: iconSize) {
                    icon.draw(in: NSRect(x: x, y: (h - iconSize) / 2, width: iconSize, height: iconSize),
                              from: .zero, operation: .sourceOver, fraction: 1)
                }
                x += p.iconW
                drewBlock = true
            }

            if p.metricsW > 0 {
                if drewBlock { x += blockGap }
                drawMetrics(ctx, p: p, x: x, ink: ink)
                x += p.metricsW
                drewBlock = true
            }

            if p.speedW > 0 {
                if drewBlock { x += blockGap }
                drawSpeed(ctx, m: m, p: p, x: x, ink: ink)
                x += p.speedW
                drewBlock = true
            }

            if p.battW > 0 {
                if drewBlock { x += blockGap }
                drawBattery(ctx, m: m, p: p, x: x, ink: ink)
            }
            return true
        }
        img.isTemplate = false
        return img
    }

    // MARK: 分块绘制

    private static func drawMetrics(_ ctx: CGContext, p: Plan, x: CGFloat, ink: NSColor) {
        switch p.layout {
        case .sideBySide:
            // 每列：标签在上、数值在下，同一条 26 pt 宽，左对齐。
            let (valueY, labelY) = columnBaselines()
            for (i, r) in p.rows.enumerated() {
                let cx = x + CGFloat(i) * (p.columnW + columnGap)
                draw(ctx, r.label, ink: ink.withAlphaComponent(labelInk), font: labelFont,
                     x: cx, baseline: labelY)
                let parts = percentParts(r.percent)
                let nw = textWidth(parts.num, valueFont)
                draw(ctx, parts.num, ink: ink.withAlphaComponent(valueInk), font: valueFont,
                     x: cx, baseline: valueY)
                if !parts.unit.isEmpty {
                    draw(ctx, parts.unit, ink: ink.withAlphaComponent(unitInk), font: unitFont,
                         x: (cx + nw + 1).rounded(), baseline: valueY)
                }
            }
        case .stacked:
            // 每行：标签在左、数值右对齐到块右沿（单位固定贴着右沿）。
            for (i, r) in p.rows.enumerated() {
                let by = stackedBaseline(i, twoRows: p.twoRows)
                draw(ctx, r.label, ink: ink.withAlphaComponent(labelInk), font: labelFont,
                     x: x, baseline: by)
                drawValue(ctx, percentParts(r.percent), ink: ink,
                          right: x + p.metricsW, baseline: by)
            }
        }
    }

    /// 数值 + 单位，右边缘对齐到 `right`。单位先落位，数字再贴上去，
    /// 这样 `9` → `100` 只让数字左移，`%` 与右边缘都不动。
    private static func drawValue(_ ctx: CGContext, _ parts: (num: String, unit: String),
                                  ink: NSColor, right: CGFloat, baseline: CGFloat) {
        let uw = parts.unit.isEmpty ? 0 : textWidth(parts.unit, unitFont)
        if !parts.unit.isEmpty {
            draw(ctx, parts.unit, ink: ink.withAlphaComponent(unitInk), font: unitFont,
                 right: right, baseline: baseline, rightAligned: true)
        }
        draw(ctx, parts.num, ink: ink.withAlphaComponent(valueInk), font: valueFont,
             right: right - uw, baseline: baseline, rightAligned: true)
    }

    private static func drawSpeed(_ ctx: CGContext, m: MenuBarViewModel, p: Plan, x: CGFloat, ink: NSColor) {
        let numX = x + wArrow + speedGap
        let unitX = numX + wSpeedNum + speedGap
        for (i, isUp) in [true, false].enumerated() {
            let by = stackedBaseline(i, twoRows: p.twoRows)
            let r = rate(isUp ? m.up : m.down)
            drawArrow(ctx, up: isUp, baseline: by, x: x, ink: ink.withAlphaComponent(speedInk))
            draw(ctx, r.num, ink: ink.withAlphaComponent(speedInk), font: speedFont,
                 right: numX + wSpeedNum, baseline: by, rightAligned: true)
            draw(ctx, r.unit, ink: ink.withAlphaComponent(unitInk), font: unitFont,
                 x: unitX, baseline: by)
        }
    }

    /// 电池：数值在 26 pt 槽里**居中**（与图标共用一个视觉重心），单位 8.5 pt。
    private static func drawBattery(_ ctx: CGContext, m: MenuBarViewModel, p: Plan, x: CGFloat, ink: NSColor) {
        let midY = height / 2
        if let pct = p.batteryPercent {
            let num = "\(min(100, max(0, pct)))"
            let nw = textWidth(num, battFont)
            let uw = textWidth("%", unitFont)
            let groupW = nw + 1 + uw
            let start = x + ((wBattPct - groupW) / 2).rounded()
            let baseline = ((height - battFont.capHeight) / 2).rounded()
            draw(ctx, num, ink: ink.withAlphaComponent(valueInk), font: battFont,
                 x: start, baseline: baseline)
            draw(ctx, "%", ink: ink.withAlphaComponent(unitInk), font: unitFont,
                 x: (start + nw + 1).rounded(), baseline: baseline)
        }
        if let st = p.batteryState {
            let gx = x + (p.batteryPercent != nil ? wBattPct + battGap : 0)
            let gw = BatteryGlyph.size.width.rounded(.up)
            let glyph = BatteryGlyph.image(state: st, color: ink)
            glyph.draw(in: NSRect(x: gx, y: midY - BatteryGlyph.size.height / 2,
                                  width: gw, height: BatteryGlyph.size.height),
                       from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    // MARK: 基线

    /// 上下排列：标签与数值在同一基线上，所以行高由**数值**的 cap 决定。
    /// 两行时 = cap·2 + lineGap，整体垂直居中（墨迹才真正居中，而非按 ascender 排）。
    private static func stackedBaseline(_ index: Int, twoRows: Bool) -> CGFloat {
        let cap = valueFont.capHeight
        let blockH = twoRows ? cap * 2 + lineGap : cap
        let bottom = (height - blockH) / 2
        let b = twoRows ? bottom + CGFloat(1 - index) * (cap + lineGap) : bottom
        return b.rounded()
    }

    /// 并排两列：标签在上（9 pt）、数值在下（11 pt），块高 = capLabel + gap + capValue。
    private static func columnBaselines() -> (value: CGFloat, label: CGFloat) {
        let capV = valueFont.capHeight
        let capL = labelFont.capHeight
        let blockH = capL + lineGap + capV
        let bottom = ((height - blockH) / 2).rounded()
        return (bottom, (bottom + capV + lineGap).rounded())
    }

    /// CTLine 的排版宽度，用于定宽槽内居中 / 右对齐。
    static func textWidth(_ s: String, _ font: NSFont) -> CGFloat {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: s, attributes: [.font: font]))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// 手绘箭头而不是用 `↑` 字符：等宽字体没有这两个字形，会 fallback、宽度不可控。
    private static func drawArrow(_ ctx: CGContext, up: Bool, baseline: CGFloat, x: CGFloat, ink: NSColor) {
        // 与数值墨迹等高：固定 7 pt 会在 11 pt 数值旁边显得短一截。
        let h = valueFont.capHeight.rounded()
        let headW: CGFloat = 4
        let headH: CGFloat = 2
        let cx = (x + wArrow / 2).rounded() + 0.5   // 1 px 竖线落在像素中心
        let bottom = baseline
        let top = bottom + h
        let tip = up ? top : bottom
        let tail = up ? bottom : top

        ctx.saveGState()
        ctx.setStrokeColor(ink.cgColor)
        ctx.setLineWidth(1.2)
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        ctx.move(to: CGPoint(x: cx, y: tail))
        ctx.addLine(to: CGPoint(x: cx, y: tip))
        let dy: CGFloat = up ? -headH : headH
        ctx.move(to: CGPoint(x: cx - headW / 2, y: tip + dy))
        ctx.addLine(to: CGPoint(x: cx, y: tip))
        ctx.addLine(to: CGPoint(x: cx + headW / 2, y: tip + dy))
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// `CTLineDraw` 的 y 是**明确的 baseline**（flipped=false 上下文里从底算）。
    ///
    /// v2.9 曾换成 `NSString.draw(at:)`，但在 `NSImage(drawingHandler:)` 里它的 y 不是
    /// baseline：实测同一个字体、y=14.3 时，CTLineDraw 的墨迹在 top-origin y=2..9，
    /// NSString.draw 却在 y=0..6 —— **整体上移 2.5~3 pt**，上行文字被菜单栏顶边裁掉。
    private static func draw(_ ctx: CGContext, _ s: String, ink: NSColor, font: NSFont,
                             x: CGFloat? = nil, right: CGFloat = 0, baseline: CGFloat,
                             rightAligned: Bool = false) {
        let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: ink])
        let line = CTLineCreateWithAttributedString(attr)
        var px = x ?? 0
        if rightAligned { px = right - textWidth(s, font) }
        ctx.textPosition = CGPoint(x: px.rounded(), y: baseline)
        CTLineDraw(line, ctx)
    }
}

/// 状态项最左的图标：`icons/VitalBar-Menubar-24.svg` 转出的单色 template PNG。
///
/// `NSImage.isTemplate` 只在 NSImageView / NSButton 里由系统自动着色，而状态项内容是
/// 我们手工画进自绘位图的，所以必须自己把形状染成菜单栏的 ink（深色条→白，浅色条→黑）。
private enum MenubarIcon {
    static let base: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenubarIcon", withExtension: "png"),
              let img = NSImage(contentsOf: url) else { return nil }
        return img
    }()

    /// 渲染路径只在主线程跑；两种 ink 各缓存一份，不必每帧重新离屏合成。
    private static var cache: [NSColor: NSImage] = [:]

    static func tinted(_ ink: NSColor, size: CGFloat) -> NSImage? {
        guard let base else { return nil }
        if let hit = cache[ink] { return hit }
        let out = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            ink.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
        cache[ink] = out
        return out
    }
}

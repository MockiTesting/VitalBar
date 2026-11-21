// SPDX-License-Identifier: MIT

import SwiftUI

/// 弹框里的小零件（规格 v1.2）。三件新的：`GlyphView`（自绘指标字形）、
/// `LevelBar`（20 段整数电平条）、`SectionLabel`（块标题）。
///
/// 为什么字形不用 SF Symbol：符号的笔画粗细与光学尺寸随系统版本变，四枚并排时
/// 很难同一重量；自绘才能保证同一 `stroke` 1.8、同一 24 网格、同一 22 pt 落点。
/// 为什么电平条不用 20 个视图：每秒重建一次，20 段 × 4 行 = 80 个视图只为画 80 个矩形。

// MARK: - 指标字形

enum GlyphKind { case cpu, gpu, mem, disk, flow }

/// 24 网格、stroke 1.8、圆头端点。坐标直接照抄规格稿的 SVG，所以改稿即改这里。
struct GlyphView: View {
    let kind: GlyphKind
    var size: CGFloat = 22
    var color: Color

    var body: some View {
        // 先把 24 网格缩放到目标尺寸再描边，线宽才不会跟着一起缩：
        // 直接用 scaleEffect 的话 1.8 会变成 1.65，1× 屏上一圈都是灰边。
        let s = size / 24
        return path
            .applying(CGAffineTransform(scaleX: s, y: s))
            .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }

    private var path: Path {
        var p = Path()
        switch kind {
        case .cpu:
            p.addRoundedRect(in: CGRect(x: 6.5, y: 6.5, width: 11, height: 11), cornerSize: CGSize(width: 2, height: 2))
            p.addRoundedRect(in: CGRect(x: 9.6, y: 9.6, width: 4.8, height: 4.8), cornerSize: CGSize(width: 1, height: 1))
            // 八根引脚：上下各两根、左右各两根，长度 3.1，离裸片 0.1 pt 留缝
            for x in [CGFloat(9.5), 14.5] {
                p.move(to: CGPoint(x: x, y: 3.4)); p.addLine(to: CGPoint(x: x, y: 6.5))
                p.move(to: CGPoint(x: x, y: 17.5)); p.addLine(to: CGPoint(x: x, y: 20.6))
            }
            for y in [CGFloat(9.5), 14.5] {
                p.move(to: CGPoint(x: 3.4, y: y)); p.addLine(to: CGPoint(x: 6.5, y: y))
                p.move(to: CGPoint(x: 17.5, y: y)); p.addLine(to: CGPoint(x: 20.6, y: y))
            }

        case .gpu:
            // 等距立方体：顶面菱形 + 左侧面 + 中缝。三层三角会被读成警告标。
            p.move(to: CGPoint(x: 12, y: 3.2))
            p.addLine(to: CGPoint(x: 20.4, y: 7.9))
            p.addLine(to: CGPoint(x: 12, y: 12.6))
            p.addLine(to: CGPoint(x: 3.6, y: 7.9))
            p.closeSubpath()
            p.move(to: CGPoint(x: 3.6, y: 7.9))
            p.addLine(to: CGPoint(x: 3.6, y: 16.1))
            p.addLine(to: CGPoint(x: 12, y: 20.8))
            p.addLine(to: CGPoint(x: 20.4, y: 16.1))
            p.addLine(to: CGPoint(x: 20.4, y: 7.9))
            p.move(to: CGPoint(x: 12, y: 12.6))
            p.addLine(to: CGPoint(x: 12, y: 20.8))

        case .mem:
            // 四根不等高 DIMM：横条 + 一条分隔 + 四根金手指
            p.addRoundedRect(in: CGRect(x: 2.6, y: 6.2, width: 18.8, height: 8.6),
                             cornerSize: CGSize(width: 1.6, height: 1.6))
            p.move(to: CGPoint(x: 2.6, y: 9.4)); p.addLine(to: CGPoint(x: 21.4, y: 9.4))
            for x in [CGFloat(6.6), 10.8, 15, 19.2] {
                p.move(to: CGPoint(x: x, y: 14.8))
                p.addLine(to: CGPoint(x: x, y: 18.1))
            }

        case .disk:
            // 盘柱：顶面椭圆 + 两侧母线 + 两条前缘弧。盘片+指针会被读成时钟。
            p.addEllipse(in: CGRect(x: 4.6, y: 3.7, width: 14.8, height: 5.4))
            p.move(to: CGPoint(x: 4.6, y: 6.4)); p.addLine(to: CGPoint(x: 4.6, y: 17.6))
            p.move(to: CGPoint(x: 19.4, y: 6.4)); p.addLine(to: CGPoint(x: 19.4, y: 17.6))
            arc(&p, fromX: 4.6, toX: 19.4, y: 17.6, ry: 2.7)
            arc(&p, fromX: 4.6, toX: 19.4, y: 11.6, ry: 2.7)

        case .flow:
            // 双源 → 单汇的抽象：两个小方块喂一个大方块
            p.addRoundedRect(in: CGRect(x: 2.4, y: 3.4, width: 6.4, height: 6),
                             cornerSize: CGSize(width: 1.4, height: 1.4))
            p.addRoundedRect(in: CGRect(x: 2.4, y: 14.6, width: 6.4, height: 6),
                             cornerSize: CGSize(width: 1.4, height: 1.4))
            p.addRoundedRect(in: CGRect(x: 15.2, y: 9, width: 6.4, height: 6),
                             cornerSize: CGSize(width: 1.4, height: 1.4))
            p.move(to: CGPoint(x: 8.8, y: 6.4))
            p.addLine(to: CGPoint(x: 12.2, y: 6.4))
            p.addLine(to: CGPoint(x: 12.2, y: 15))
            p.addLine(to: CGPoint(x: 15.2, y: 15))
            p.move(to: CGPoint(x: 8.8, y: 17.6))
            p.addLine(to: CGPoint(x: 12.2, y: 17.6))
        }
        return p
    }

    /// 半椭圆前缘：三次贝塞尔的最大深度 = 0.75·k，要得到 ry 就得取 k = 4·ry/3。
    private func arc(_ p: inout Path, fromX: CGFloat, toX: CGFloat, y: CGFloat, ry: CGFloat) {
        let k = ry * 4 / 3
        p.move(to: CGPoint(x: fromX, y: y))
        p.addCurve(to: CGPoint(x: toX, y: y),
                   control1: CGPoint(x: fromX, y: y + k),
                   control2: CGPoint(x: toX, y: y + k))
    }
}

// MARK: - 电平条

/// 20 段整数电平条：20 × 3 + 19 × 1 = 79 pt，全部整数，1× 屏上没有半像素缝。
///
/// 三段颜色由 `thresholds` 推出的**段号**决定（60/85 → 12/17；磁盘 75/90 → 15/18），
/// 不写死。零散地用 4 条 `Path` 各填一次，是 4 个绘制层，不是 80 个视图。
struct LevelBar: View {
    var percent: Double
    var kind: MetricKind
    var width: CGFloat = 79
    var height: CGFloat = 14

    private let segments = 20
    private let segW: CGFloat = 3
    private let gap: CGFloat = 1

    private var lit: Int {
        min(segments, max(0, Int((percent / 5).rounded())))
    }

    var body: some View {
        let t = kind.thresholds
        var track = Path(), identity = Path(), warn = Path(), alert = Path()
        let n = lit
        for i in 0..<segments {
            let r = CGRect(x: CGFloat(i) * (segW + gap), y: 0, width: segW, height: height)
            let seg = Path(roundedRect: r, cornerRadius: 1)
            if i >= n { track.addPath(seg) }
            else if i >= t.alertSegment { alert.addPath(seg) }
            else if i >= t.warnSegment { warn.addPath(seg) }
            else { identity.addPath(seg) }
        }
        return ZStack(alignment: .topLeading) {
            track.fill(ThemeColor.track)
            identity.fill(ThemeColor.identity(kind))
            // 段带用更亮一档的琥珀：色块要比的是左右邻居，不是卡片底色。
            warn.fill(ThemeColor.warnBar)
            alert.fill(ThemeColor.alert)
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

// MARK: - 块标题

/// 10 pt 等宽半粗 + 13 pt 字形。规格里的 `.sect`：比副标题重一档，但比数值轻得多。
struct SectionLabel: View {
    let text: String
    var glyph: GlyphKind?
    var color: Color = ThemeColor.ink2

    var body: some View {
        HStack(spacing: 5) {
            if let glyph {
                GlyphView(kind: glyph, size: 13, color: color)
            }
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(0.3)
                .lineLimit(1)
        }
        .foregroundStyle(color)
    }
}

// MARK: - 胶囊

struct Chip: View {
    let text: String
    /// 默认是顶部信息条的胶囊墨色；别处若要用更亮的字，显式传 `ThemeColor.ink2`。
    var color: Color = ThemeColor.headerChip

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(color)
            // 顶部信息条一行塞 3 个 Chip + 运行时长。没有 fixedSize 时 SwiftUI 会在
            // 空间紧张时压缩 Text，把 `Apple Silicon` 截成 `Apple Sili…`；锁住理想宽度
            // 后，超宽会显式暴露而不是悄悄打省略号（v2.9 芯片名已压成 `M1`）。
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ThemeColor.chip))
    }
}

// MARK: - 卡片

struct GlassCard<Content: View>: View {
    var padding: CGFloat = 10
    var corner: CGFloat = 10
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: corner, style: .continuous).fill(ThemeColor.card))
            .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(ThemeColor.hairline, lineWidth: 1))
    }
}

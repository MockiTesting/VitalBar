// SPDX-License-Identifier: MIT

import AppKit
import CoreGraphics
import Foundation

// VitalBar 菜单栏电池字形 v4.0
//
// 结构（27 × 13 pt，纯线稿，无电量填充）：
//   电池外壳 23.50 × 10.60（描边 1.10，外沿 y 1.20–11.80）+ 右侧电极
//   插头 6.10 × 13.00，从图标顶边一直画到底边 —— 上下贯穿外壳，不是「装在壳里」
//   状态符 6.13 × 7.00，位于插头右侧
//
// 电量不由图标表达：填充条已去掉，电量只由旁边的百分比文字读出。
let W: CGFloat = 27
let H: CGFloat = 13
let stroke: CGFloat = 1.10

// 外壳按「外沿」定尺寸，绘制路径再内缩半个描边，避免描边溢出画布
let shellOuter = CGRect(x: 0.70, y: 1.20, width: 23.50, height: 10.60)   // 0.70–24.20 × 1.20–11.80
let shellPath = shellOuter.insetBy(dx: stroke / 2, dy: stroke / 2)
let electrodeRect = CGRect(x: 24.30, y: 4.35, width: 2.10, height: 4.30)  // 与外壳右描边搭接 0.1
// 内壁：外壳外沿再向内让出描边
let inner = shellOuter.insetBy(dx: stroke, dy: stroke)                    // 1.80–23.10 × 2.30–10.70

enum BState: String { case charging, pause, discharging, unplugged }

/// 插头：自上而下四段，整高 13.00 —— 与图标同高，上下都伸到画布边缘。
///
///   ① 两枚引脚 1.64 × 2.80（针距 0.96，圆头）
///   ② 阔身 6.10 × 4.20（顶角 0.82）—— 最宽处，宽/高 ≈ 0.47
///   ③ 收腰 6.10 → 1.82，高 2.00，用 `addCurve` 画凹肩（直线斜切会读成「酒杯」）
///   ④ 尾柱 1.82 × 4.00，底边小圆角
///
/// 四段缺一不可：只画「两针 + 一个圆角方块」时，1× 下会被读成插排而不是插头。
func plugPath(x: CGFloat, y: CGFloat, bw: CGFloat = 5.70, h: CGFloat = 13.00) -> CGPath {
    let k = bw / 5.70
    let ky = h / 13.00
    let prongW = 1.80 * k, gap = 1.05 * k
    let prongH = 2.80 * ky, bodyH = 4.20 * ky, taperH = 2.00 * ky
    let stemW = 2.00 * k
    let stemH = h - prongH - bodyH - taperH
    let p = CGMutablePath()

    // ① 两枚引脚
    let span = prongW * 2 + gap
    let px0 = x + (bw - span) / 2
    let pr = min(prongW, prongH) * 0.45
    p.addRoundedRect(in: CGRect(x: px0, y: y, width: prongW, height: prongH + 0.10),
                     cornerWidth: pr, cornerHeight: pr)
    p.addRoundedRect(in: CGRect(x: px0 + prongW + gap, y: y, width: prongW, height: prongH + 0.10),
                     cornerWidth: pr, cornerHeight: pr)

    // ②③④ 一条连续轮廓：阔身 → 凹肩收腰 → 尾柱
    let top = y + prongH
    let cx = x + bw / 2, tw = stemW / 2
    let ty = top + bodyH          // 收腰起点
    let ey = ty + taperH          // 收腰终点（尾柱顶）
    let r: CGFloat = 0.90 * k
    let b = CGMutablePath()
    b.move(to: CGPoint(x: x + r, y: top))
    b.addLine(to: CGPoint(x: x + bw - r, y: top))
    b.addQuadCurve(to: CGPoint(x: x + bw, y: top + r), control: CGPoint(x: x + bw, y: top))
    b.addLine(to: CGPoint(x: x + bw, y: ty))
    b.addCurve(to: CGPoint(x: cx + tw, y: ey),
               control1: CGPoint(x: x + bw - 0.10 * k, y: ty + taperH * 0.62),
               control2: CGPoint(x: cx + tw + 0.70 * k, y: ey - taperH * 0.18))
    b.addLine(to: CGPoint(x: cx + tw, y: ey + stemH - 0.55 * k))
    b.addQuadCurve(to: CGPoint(x: cx + tw - 0.55 * k, y: ey + stemH),
                   control: CGPoint(x: cx + tw, y: ey + stemH))
    b.addLine(to: CGPoint(x: cx - tw + 0.55 * k, y: ey + stemH))
    b.addQuadCurve(to: CGPoint(x: cx - tw, y: ey + stemH - 0.55 * k),
                   control: CGPoint(x: cx - tw, y: ey + stemH))
    b.addLine(to: CGPoint(x: cx - tw, y: ey))
    b.addCurve(to: CGPoint(x: x, y: ty),
               control1: CGPoint(x: cx - tw - 0.70 * k, y: ey - taperH * 0.18),
               control2: CGPoint(x: x + 0.10 * k, y: ty + taperH * 0.62))
    b.addLine(to: CGPoint(x: x, y: top + r))
    b.addQuadCurve(to: CGPoint(x: x + r, y: top), control: CGPoint(x: x, y: top))
    b.closeSubpath()
    p.addPath(b)
    return p
}

// 插头与状态符在内壁中整体居中：5.70 + 1.60 + 6.13 = 13.43，两侧各余 3.94
let plugX: CGFloat = 5.74
let plugY: CGFloat = 0.00
let symCx: CGFloat = 16.08
/// 悬空时的状态符（未接电：没有插头，短横居中）
let idleCx: CGFloat = inner.midX

/// 状态符：加号（充电）/ 双竖条（暂停）/ 减号（接电但放电）/ 短横（未接电）
/// 尺寸 6.13 × 7.00，臂宽 1.80。充电用加号而非闪电——13 pt 高的闪电会被压成折线。
func symbolPath(_ s: BState) -> CGPath {
    let p = CGMutablePath()
    let cx = (s == .unplugged) ? idleCx : symCx
    let cy = H / 2
    let arm: CGFloat = 1.80
    let wide: CGFloat = 6.13
    let tall: CGFloat = 7.00
    switch s {
    case .charging:
        p.addRoundedRect(in: CGRect(x: cx - wide / 2, y: cy - arm / 2, width: wide, height: arm),
                         cornerWidth: arm / 2, cornerHeight: arm / 2)
        p.addRoundedRect(in: CGRect(x: cx - arm / 2, y: cy - tall / 2, width: arm, height: tall),
                         cornerWidth: arm / 2, cornerHeight: arm / 2)
    case .pause:
        let barW: CGFloat = 1.75, gap: CGFloat = 2.10
        for dx in [-(barW + gap / 2), gap / 2] {
            p.addRoundedRect(in: CGRect(x: cx + dx, y: cy - tall / 2, width: barW, height: tall),
                             cornerWidth: barW / 2, cornerHeight: barW / 2)
        }
    case .discharging, .unplugged:
        p.addRoundedRect(in: CGRect(x: cx - wide / 2, y: cy - arm / 2, width: wide, height: arm),
                         cornerWidth: arm / 2, cornerHeight: arm / 2)
    }
    return p
}

/// 插头穿过外壳上下描边时，沿轮廓挖掉 0.30 的空隙。
/// 只做「同色并集」的话，插头会和外壳横线粘成一根，读起来像挂在壳上；挖缝后才看得出是穿孔。
let plugHalo: CGFloat = 0.30

func draw(_ s: BState, scale: CGFloat, white: Bool = false) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * scale), pixelsHigh: Int(H * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    let cg = NSGraphicsContext.current!.cgContext
    cg.translateBy(x: 0, y: H); cg.scaleBy(x: 1, y: -1); cg.setShouldAntialias(true)
    let ink = white ? CGColor(red: 1, green: 1, blue: 1, alpha: 1) : CGColor(red: 0, green: 0, blue: 0, alpha: 1)
    cg.setFillColor(ink); cg.setStrokeColor(ink)

    // 外壳 + 电极
    cg.setLineWidth(stroke)
    cg.addPath(CGPath(roundedRect: shellPath, cornerWidth: 3.0, cornerHeight: 3.0, transform: nil))
    cg.strokePath()
    cg.addPath(CGPath(roundedRect: electrodeRect, cornerWidth: 0.85, cornerHeight: 0.85, transform: nil))
    cg.fillPath()

    // 插头（仅接电时）：先挖缝，再实心填充
    if s != .unplugged {
        let pl = plugPath(x: plugX, y: plugY)
        cg.saveGState()
        cg.setBlendMode(.clear)
        cg.setLineWidth(plugHalo * 2)
        cg.addPath(pl)
        cg.strokePath()
        cg.restoreGState()
        cg.setFillColor(ink)
        cg.addPath(pl)
        cg.fillPath()
    }

    cg.addPath(symbolPath(s))
    cg.fillPath()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let outDir = URL(fileURLWithPath: "/tmp/batt_v40")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let states: [BState] = [.charging, .pause, .discharging, .unplugged]
for st in states {
    for sc in [1.0, 2.0, 3.0] {
        let rep = draw(st, scale: CGFloat(sc))
        let suf = sc == 1 ? "" : "@\(Int(sc))x"
        try! rep.representation(using: .png, properties: [:])!
            .write(to: outDir.appendingPathComponent("\(st.rawValue)\(suf).png"))
    }
}

// ---- 验证图 1：四态 × 浅深底，各给 1× 与 3× ----
let cw: CGFloat = 780, ch: CGFloat = 230
let crep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(cw * 2), pixelsHigh: Int(ch * 2),
                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
crep.size = NSSize(width: cw, height: ch)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: crep)!
let cg2 = NSGraphicsContext.current!.cgContext
cg2.setFillColor(CGColor(red: 0.96, green: 0.96, blue: 0.97, alpha: 1))
cg2.fill(CGRect(x: 0, y: 0, width: cw, height: ch / 2))
cg2.setFillColor(CGColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1))
cg2.fill(CGRect(x: 0, y: ch / 2, width: cw, height: ch / 2))
cg2.interpolationQuality = .none
for (di, dark) in [(0, false), (1, true)] {
    for (i, st) in states.enumerated() {
        for (j, sc) in [(0, CGFloat(1.0)), (1, CGFloat(3.0))] {
            let img = draw(st, scale: sc, white: dark).cgImage!
            let rect = CGRect(x: 30 + CGFloat(i) * 186 + CGFloat(j) * (W + 22),
                              y: CGFloat(di) * (ch / 2) + 50, width: W * sc, height: H * sc)
            cg2.draw(img, in: rect)
        }
    }
}
NSGraphicsContext.restoreGraphicsState()
try! crep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("states.png"))

// ---- 验证图 2：1× 真实像素放大 8 倍 ----
let px = 8
let pcellW = Int(W) * px + 26, pcellH = Int(H) * px + 26
let pw = CGFloat(pcellW * 4), ph = CGFloat(pcellH * 2)
let prep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pw), pixelsHigh: Int(ph),
                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
prep.size = NSSize(width: pw, height: ph)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: prep)!
let cg4 = NSGraphicsContext.current!.cgContext
cg4.setFillColor(CGColor(red: 0.97, green: 0.97, blue: 0.98, alpha: 1)); cg4.fill(CGRect(x: 0, y: 0, width: pw, height: ph / 2))
cg4.setFillColor(CGColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1)); cg4.fill(CGRect(x: 0, y: ph / 2, width: pw, height: ph / 2))
cg4.interpolationQuality = .none
for (di, dark) in [(0, false), (1, true)] {
    for (i, st) in states.enumerated() {
        let img = draw(st, scale: 1, white: dark).cgImage!
        let rect = CGRect(x: CGFloat(i * pcellW + 12), y: CGFloat(di) * ph / 2 + 12,
                          width: CGFloat(Int(W) * px), height: CGFloat(Int(H) * px))
        cg4.saveGState()
        cg4.translateBy(x: rect.minX, y: rect.minY + rect.height); cg4.scaleBy(x: 1, y: -1)
        cg4.clip(to: CGRect(x: 0, y: 0, width: rect.width, height: rect.height), mask: img)
        cg4.setFillColor(dark ? CGColor(red: 0.93, green: 0.93, blue: 0.94, alpha: 1)
                              : CGColor(red: 0.10, green: 0.10, blue: 0.11, alpha: 1))
        cg4.fill(CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        cg4.restoreGState()
    }
}
NSGraphicsContext.restoreGraphicsState()
try! prep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("pixel-1x.png"))

print("v4.0 rendered")

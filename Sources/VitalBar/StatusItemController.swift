// SPDX-License-Identifier: MIT

import AppKit
import SwiftUI

/// 弹框面板：无边框、不抢焦点、圆角由 SwiftUI 自己裁（窗口透明时系统阴影会跟着内容形状走）。
final class PopupPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }   // Esc
        super.keyDown(with: event)
    }
}

/// 状态项：点击弹框；设置与退出在弹框底部（与 参考日历应用 一致），不再走右键。
///
/// 关键约束：状态项的颜色必须取自 `button.effectiveAppearance`，**不能**取 `NSApp.effectiveAppearance`。
/// 外观覆盖只作用于弹框与设置窗口，一旦用全局外观决定菜单栏文字色，用户在浅色系统下选「深色」
/// 就会把白字压在白菜单栏上——直接不可读。
final class StatusItemController: NSObject {
    /// 必须**惰性**创建：在 `applicationDidFinishLaunching` 之前（属性初始化阶段）
    /// 就调 `NSStatusBar.system.statusItem` 会拿到一个「窗口存在但永不被合成」的项——
    /// 窗口列表里能看到 199x24 的窗口，`kCGWindowIsOnscreen` 却是 0，屏幕上永远空着。
    private var statusItem: NSStatusItem! = nil
    private var popup: PopupPanel?
    private var settingsWindow: NSWindow?
    private var lastSnapshot = Snapshot()
    private var debugPanel: NSWindow?
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var resignObserver: NSObjectProtocol?

    /// 弹框或验证窗口只要有一个开着，就要把每帧推给界面
    private var panelVisible: Bool {
        (popup?.isVisible ?? false) || (debugPanel?.isVisible ?? false)
    }

    func install() {
        // 在这里（launch 之后）才创建状态项，理由见 statusItem 的注释
        if statusItem == nil {
            // 初值给「当前偏好下的真实宽度」而不是 variableLength：
            // 用可变长度创建过的项在某些情况下不会被合成（见类注释第 2 段）。
            let probe = MenuBarViewModel(rows: [], up: 0, down: 0,
                                         battery: BatteryRead(), batteryState: .unplugged)
            statusItem = NSStatusBar.system.statusItem(
                withLength: MenuBarRenderer.width(probe, prefs: Prefs.shared))
        }
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageOnly
        // 不能用 .scaleNone：它会无视 NSBitmapImageRep 的逻辑尺寸（size），
        // 直接把位图的**像素**尺寸当点画出来，2× 位图于是被放大成两倍大，
        // 在 24pt 高的菜单栏里只露出第一行文字。等比缩放在固定长度下不会缩。
        button.imageScaling = .scaleProportionallyDown
        button.action = #selector(handleClick(_:))
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("VitalBar")
        render(with: lastSnapshot)
        SamplerHub.shared.onTick = { [weak self] s in
            self?.lastSnapshot = s
            self?.render(with: s)
            if self?.panelVisible == true { PopupBridge.shared.ingest(s) }
        }
        // 改设置立刻重画，不用等下一个 1 s tick
        NotificationCenter.default.addObserver(forName: Prefs.changed, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.render(with: self.lastSnapshot)
        }
        SamplerHub.shared.start()
    }

    /// 菜单栏文字色：跟随菜单栏**自身**的外观，而不是 app 的
    private var ink: NSColor {
        guard let appearance = statusItem.button?.effectiveAppearance else { return .labelColor }
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .white : .black
    }

    private func render(with s: Snapshot) {
        guard let button = statusItem.button else { return }
        let prefs = Prefs.shared
        let rows = [prefs.slot1, prefs.slot2].compactMap { metric -> MenuBarRow? in
            guard !metric.isOff else { return nil }
            return MenuBarRow(label: metric.label, percent: percent(for: metric, s: s))
        }
        let model = MenuBarViewModel(rows: rows, up: s.up, down: s.down,
                                     battery: s.battery, batteryState: s.batteryState)
        let img = MenuBarRenderer.image(model, prefs: prefs, ink: ink)
        apply(img, to: button)
        if UserDefaults.standard.bool(forKey: "vitalbar.debugDump") {
            Self.savePNG(img, "/tmp/vitalbar-live.png")
        }
        Dbg.log("render img=\(img.size.width)x\(img.size.height) rows=\(rows.count) layout=\(prefs.layout.rawValue) content=\(prefs.content.rawValue)")
    }

    /// 把图装进按钮。
    ///
    /// `length` 只在宽度真的变了时才改动：一是没必要每秒触发状态栏重排，
    /// 二是「先定长度、再给图」的顺序更稳（重排会牵动按钮的 imageRect）。
    private func apply(_ img: NSImage, to button: NSStatusBarButton) {
        let w = img.size.width
        if abs(statusItem.length - w) > 0.01 { statusItem.length = w }
        button.image = img
    }

    private static func savePNG(_ img: NSImage, _ path: String) {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }

    private func percent(for metric: Prefs.Metric, s: Snapshot) -> Double? {
        switch metric {
        case .cpu: return s.cpu
        case .memory: return s.memory
        case .gpu: return s.gpu
        case .disk: return s.disk
        case .off: return nil
        }
    }

    // MARK: 交互

    @objc private func handleClick(_ sender: NSStatusBarButton) { togglePopup() }

    private     func togglePopup() {
        if let p = popup, p.isVisible { closePopup(); return }

        // 功率缓存由 SamplerHub 常驻维护；若正好赶上启动后的第一个 tick 之前，
        // 再从 hub 取一次，保证首帧就不是「正在读取功率…」的空卡片。
        var first = lastSnapshot
        if first.power == nil { first.power = SamplerHub.shared.latest.power }
        let host = NSHostingView(rootView: makePopup(first, PopupBridge.shared.history))
        host.frame = NSRect(x: 0, y: 0, width: PopupView.width, height: 10)
        host.layoutSubtreeIfNeeded()
        applyLook(to: host)
        let h = max(host.fittingSize.height, 200)

        let panel = PopupPanel(contentRect: NSRect(x: 0, y: 0, width: PopupView.width, height: h),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = host
        // 外观覆盖必须落到**窗口**上，而不只是 contentView。系统是深色、app 里选浅色时，
        // 只给 view 设 .aqua 会让 .ultraThinMaterial 仍按窗口的 darkAqua 合成，
        // 在浅色面板外沿留下一条近黑的 1px 材质描边（v3.2 实测 rgb 32,33,33）。
        applyLook(to: panel)
        panel.onCancel = { [weak self] in self?.closePopup() }

        PopupBridge.shared.reset(with: lastSnapshot)
        PopupBridge.shared.onUpdate = { [weak self, weak host] s, hist in
            host?.rootView = self?.makePopup(s, hist) ?? AnyView(EmptyView())
        }
        popup = panel
        SamplerHub.shared.wantsPower = true
        // hosting view 靠约束把窗口撑到内容高度，但自适应要等窗口上屏后才生效：
        // 先透明上屏 → 下一帧布局完再定位并显形，避免按错误高度定位后顶到屏幕外。
        panel.alphaValue = 0
        panel.setFrameOrigin(NSPoint(x: -9999, y: -9999))
        panel.orderFrontRegardless()
        // 只有真的拿到焦点，Esc 才收得到；拿不到也不影响鼠标操作
        panel.makeKey()
        startDismissMonitors()
        DispatchQueue.main.async { [weak self, weak panel, weak host] in
            guard let self, let panel else { return }
            panel.layoutIfNeeded()
            Dbg.log("popup measure host.fit=\(String(describing: host?.fittingSize)) panel=\(panel.frame)")
            self.place(panel)
            panel.alphaValue = 1
            Dbg.log("popup placed frame=\(panel.frame)")
        }
    }

    /// 弹框落在**鼠标所在的那块屏**上，水平居中对齐鼠标，竖直贴在菜单栏下沿。
    /// 用 NSPopover 时它只会认主屏那份状态栏窗口，双屏下点内屏的项会弹到外接屏去。
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = forcedScreen()
            ?? NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? statusItem.button?.window?.screen
        guard let screen else { panel.center(); return }

        let w = panel.frame.width, h = panel.frame.height
        let menubar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
        var x = mouse.x - w / 2
        let minX = screen.frame.minX + 8
        let maxX = screen.frame.maxX - w - 8
        x = min(max(x, minX), max(minX, maxX))
        let y = screen.frame.maxY - menubar - h - 6
        panel.setFrameOrigin(NSPoint(x: x.rounded(), y: y.rounded()))
    }

    /// 验证用：强制把弹框放到内建屏（只在本次 debug 打开时生效，用完即清）
    private var forceBuiltinOnce = false
    private func forcedScreen() -> NSScreen? {
        guard forceBuiltinOnce else { return nil }
        forceBuiltinOnce = false
        return Self.builtinScreen()
    }

    private func makePopup(_ s: Snapshot, _ hist: HUDHistory) -> AnyView {
        AnyView(PopupContainer {
            PopupView(snapshot: s, history: hist,
                      onSettings: { [weak self] in self?.openSettingsFromPopup() },
                      onQuit: { NSApp.terminate(nil) })
        })
    }

    func closePopup() {
        popup?.orderOut(nil)
        popup = nil
        SamplerHub.shared.wantsPower = debugPanel?.isVisible == true
        stopDismissMonitors()
    }

    /// 点弹框以外的任何地方都要收起弹框（需求：点别的窗口弹框不消失）。
    /// 全局监听负责「点到别的 app」，本地监听负责「点到本 app 的其它窗口」，
    /// 失活通知兜住「切到别的 app 但没点到窗口」（⌘Tab、手势切 Space）。
    private func startDismissMonitors() {
        stopDismissMonitors()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopup()
        }
        Dbg.log("dismiss monitors global=\(clickMonitor != nil)")
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let p = self.popup, p.isVisible else { return event }
            // 点在状态项自己身上交给 button 的 action 处理，否则会「先关再开」闪一下
            if event.window === self.statusItem.button?.window { return event }
            if event.window !== p { self.closePopup() }
            return event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.closePopup()
        }
    }

    private func stopDismissMonitors() {
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        if let m = localClickMonitor { NSEvent.removeMonitor(m); localClickMonitor = nil }
        if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
    }

    private func openSettingsFromPopup() {
        closePopup()
        showSettings()
    }

    /// 本机 AXIsProcessTrusted = false，自动化点不到状态项；这两个入口只用于本地验证。
    ///
    /// v1.2：不再强制内屏。双屏验证要在这两块屏上各看一次，而 `place()` 本来就按
    /// 鼠标所在屏定位——把鼠标挪过去再开，就是那块屏；强制内屏反而挡住了外接 1× 屏。
    func debugOpenPopup() {
        togglePopup()
    }

    func debugOpenSettings() {
        showSettings()
    }

    /// 验证用：把弹框内容放进一个**内屏**居中的普通窗口。
    /// 不这样做的话，调试弹框会跟着主屏那块状态项跑到外接屏上去。
    func debugPanelOnBuiltin() {
        PopupBridge.shared.reset(with: lastSnapshot)
        let host = NSHostingController(rootView: makePopup(lastSnapshot, PopupBridge.shared.history))
        let h = max(host.view.fittingSize.height, 320)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: PopupView.width, height: h),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "VitalBar 弹框"
        w.isReleasedWhenClosed = false
        w.contentViewController = host
        SamplerHub.shared.wantsPower = true
        PopupBridge.shared.onUpdate = { [weak self, weak host] s, hh in
            host?.rootView = self?.makePopup(s, hh) ?? AnyView(EmptyView())
        }
        if let builtin = Self.builtinScreen() {
            let f = builtin.visibleFrame
            w.setFrameOrigin(NSPoint(x: f.midX - PopupView.width / 2, y: f.midY - h / 2))
        } else {
            w.center()
        }
        debugPanel = w
        applyLook(to: w)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 内建屏（本机为 1440×900 @2x）。验证一律只在这块屏上做，外接屏不参与。
    static func builtinScreen() -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
        }
    }

    private func showSettings() {
        if let w = settingsWindow {
            applyLook(to: w)
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        Dbg.log("showSettings")
        // 高度由 SwiftUI 的内在尺寸决定：不再写死 648，避免底部留一大片空白。
        let host = NSHostingView(rootView: SettingsView())
        host.frame = NSRect(x: 0, y: 0, width: 420, height: 10)
        host.layoutSubtreeIfNeeded()
        let h = max(host.fittingSize.height, 320)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: h),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "VitalBar 设置"
        w.isReleasedWhenClosed = false
        w.contentView = host
        if let builtin = Self.builtinScreen() {
            let f = builtin.visibleFrame
            w.setFrameOrigin(NSPoint(x: f.midX - 210, y: f.midY - h / 2))
        } else {
            w.center()
        }
        settingsWindow = w
        applyLook(to: w)
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Dbg.log("settings height=\(h)")
    }

    /// 外观覆盖只作用于弹框与设置窗口——菜单栏状态项永远跟随系统。
    private var lookAppearance: NSAppearance? { Prefs.shared.look.appearance }

    private func applyLook(to view: NSView?) {
        view?.appearance = lookAppearance
    }

    /// 弹框是 borderless + 透明 + 材质的窗口，材质由窗口的 effectiveAppearance 决定，
    /// 所以窗口本身也要一起覆盖，否则深浅两套会在边缘打架；而 contentView 上那份
    /// 显式外观又会压过窗口（标题栏变了正文不变就是这么来的），因此两个一起设。
    private func applyLook(to window: NSWindow?) {
        guard let window else { return }
        let ap = lookAppearance
        window.appearance = ap
        window.contentView?.appearance = ap
    }
}

/// 弹框与采样之间的桥：维护 CPU / GPU / 内存三条 30 点曲线（1 Hz）。
final class PopupBridge {
    static let shared = PopupBridge()
    private(set) var history = HUDHistory()
    var onUpdate: ((Snapshot, HUDHistory) -> Void)?

    private static let cap = 30

    func reset(with s: Snapshot) {
        // 首帧用当前值铺满，迷你图一打开就有形状，而不是从左下角爬出来
        history.cpu = Array(repeating: s.cpu, count: 10)
        history.gpu = Array(repeating: s.gpu ?? 0, count: 10)
        history.mem = Array(repeating: s.memory, count: 10)
    }

    func ingest(_ s: Snapshot) {
        history.cpu.append(s.cpu)
        history.gpu.append(s.gpu ?? 0)
        history.mem.append(s.memory)
        if history.cpu.count > Self.cap { history.cpu.removeFirst(history.cpu.count - Self.cap) }
        if history.gpu.count > Self.cap { history.gpu.removeFirst(history.gpu.count - Self.cap) }
        if history.mem.count > Self.cap { history.mem.removeFirst(history.mem.count - Self.cap) }
        onUpdate?(s, history)
    }
}

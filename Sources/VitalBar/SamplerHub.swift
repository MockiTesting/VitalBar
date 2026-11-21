// SPDX-License-Identifier: MIT

import AppKit
import Foundation

struct Snapshot {
    var cpu: Double = 0
    var memory: Double = 0
    var gpu: Double?
    var disk: Double?
    var up: Double = 0
    var down: Double = 0
    var battery = BatteryRead()
    var batteryState: BatteryState = .unplugged
    var processes: [ProcSample] = []
    var power: PowerSample?
    var totalMemory: Double = 0
}

/// 单一 1 Hz 节拍驱动全部采样。
///
/// v3.2：功率改为**常驻低频缓存**。旧逻辑只在弹框打开时采、关闭就置 nil，
/// 导致每次点开都先显示 1 秒「正在读取功率…」、卡片只有一行高，等下一次 tick
/// 才突然撑开，布局跳一下。现在启动后第一个 tick 就采一帧，之后每 4 s 续一帧；
/// 弹框打开时切到 1 Hz。点开瞬间 `lastSnapshot.power` 已经有值，直接渲染完整分流图。
final class SamplerHub {
    static let shared = SamplerHub()

    private let cpu = CPUSampler()
    private let mem = MemorySampler()
    private let net = NetSampler()
    private let batt = BatteryMonitor()
    private let procs = ProcessSampler()
    private let gpu = GPUReader()
    private let disk = DiskSampler()

    private let queue = DispatchQueue(label: (Bundle.main.bundleIdentifier ?? "VitalBar") + ".sample", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var tickCount = 0

    private(set) var latest = Snapshot()
    var onTick: ((Snapshot) -> Void)?
    /// 弹框打开时置 true：功率从 4 s 一次提速到 1 Hz；关闭后仍留着缓存。
    var wantsPower = false

    func start() {
        guard timer == nil else { return }
        latest.totalMemory = mem.totalBytes
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.2, repeating: 1.0, leeway: .milliseconds(120))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    private func tick() {
        tickCount += 1
        var s = latest
        s.cpu = cpu.sample()
        s.memory = mem.sample()
        s.gpu = gpu.utilization()
        s.disk = disk.usedPercent()
        let n = net.sample()
        s.up = n.up
        s.down = n.down
        let b = batt.sample()
        s.battery = b
        s.batteryState = batt.state
        if tickCount % 2 == 0 { s.processes = procs.sample() }
        // 首个 tick（tickCount=1）就采，之后每 4 s 续一帧；弹框开着则每 tick 都采。
        // 不采的帧沿用 latest.power（s 是从 latest 拷贝来的），缓存绝不会被清空。
        if wantsPower || tickCount % 4 == 1 { s.power = PowerReader.shared.read() }
        latest = s
        DispatchQueue.main.async { [weak self] in self?.onTick?(s) }
    }
}

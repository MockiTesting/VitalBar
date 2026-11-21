// SPDX-License-Identifier: MIT

import AppKit
import Darwin
import IOKit
import IOKit.ps

// MARK: - CPU

/// 1 Hz 原生采样：host_statistics 差分。不依赖任何外部进程。
final class CPUSampler {
    private var last: host_cpu_load_info?

    func sample() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        defer { last = info }
        guard let prev = last else { return 0 }

        func delta(_ a: UInt32, _ b: UInt32) -> Double {
            a >= b ? Double(a - b) : Double(UInt32.max - b &+ a)
        }
        let user = delta(info.cpu_ticks.0, prev.cpu_ticks.0)
        let system = delta(info.cpu_ticks.1, prev.cpu_ticks.1)
        let idle = delta(info.cpu_ticks.2, prev.cpu_ticks.2)
        let nice = delta(info.cpu_ticks.3, prev.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return 0 }
        return min(100, max(0, (user + system + nice) / total * 100))
    }
}

// MARK: - 内存

/// 口径与活动监视器一致：已用 = active + wired + compressed（不把 inactive 算作已用）。
final class MemorySampler {
    private var total: Double = 0
    private var pageSize: Double = 0

    init() {
        total = Double(ProcessInfo.processInfo.physicalMemory)
        var ps: vm_size_t = 0
        host_page_size(mach_host_self(), &ps)
        pageSize = Double(ps)
    }

    func sample() -> Double {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS, total > 0 else { return 0 }
        let used = (Double(stats.active_count) + Double(stats.wire_count) + Double(stats.compressor_page_count)) * pageSize
        return min(100, max(0, used / total * 100))
    }

    var totalBytes: Double { total }
}

// MARK: - 网速

/// NET_RT_IFLIST2 累加所有非 loopback 接口的字节数，两次采样差分。
final class NetSampler {
    private var lastIn: UInt64 = 0
    private var lastOut: UInt64 = 0
    private var lastAt = Date()

    private func read() -> (inBytes: UInt64, outBytes: UInt64) {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return (0, 0) }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return (0, 0) }

        var i = 0
        var inB: UInt64 = 0, outB: UInt64 = 0
        let hdrSize = MemoryLayout<if_msghdr>.size
        while i + hdrSize <= len {
            let msglen: Int = buf.withUnsafeBytes { raw -> Int in
                let p = raw.baseAddress!.advanced(by: i)
                return Int(p.assumingMemoryBound(to: if_msghdr.self).pointee.ifm_msglen)
            }
            let type: UInt8 = buf.withUnsafeBytes { raw in
                raw.baseAddress!.advanced(by: i).assumingMemoryBound(to: if_msghdr.self).pointee.ifm_type
            }
            if type == RTM_IFINFO2, msglen >= MemoryLayout<if_msghdr2>.size {
                let m = buf.withUnsafeBytes { raw in
                    raw.baseAddress!.advanced(by: i).assumingMemoryBound(to: if_msghdr2.self).pointee
                }
                if m.ifm_flags & IFF_LOOPBACK == 0 {
                    inB &+= m.ifm_data.ifi_ibytes
                    outB &+= m.ifm_data.ifi_obytes
                }
            }
            i += max(msglen, 1)
        }
        return (inB, outB)
    }

    /// 返回 (上行, 下行) 字节/秒
    func sample() -> (up: Double, down: Double) {
        let (inB, outB) = read()
        let now = Date()
        let dt = max(now.timeIntervalSince(lastAt), 0.001)
        defer { lastIn = inB; lastOut = outB; lastAt = now }
        guard lastIn > 0 || lastOut > 0 else { return (0, 0) }
        let down = inB >= lastIn ? Double(inB - lastIn) / dt : 0
        let up = outB >= lastOut ? Double(outB - lastOut) / dt : 0
        return (up, down)
    }
}

// MARK: - 磁盘

/// 磁盘占用：`resourceValues` 是文件系统调用，不必 1 Hz 去做——10 秒一读足够。
/// 以前菜单栏里磁盘槽永远是空值（`DISK —`），就是因为这里从来没采过。
final class DiskSampler {
    private var lastAt = Date.distantPast
    private var cached: Double?

    func usedPercent() -> Double? {
        if Date().timeIntervalSince(lastAt) < 10 { return cached }
        lastAt = Date()
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                    .volumeAvailableCapacityForImportantUsageKey]),
           let total = v.volumeTotalCapacity, total > 0,
           let free = v.volumeAvailableCapacityForImportantUsage {
            let t = Double(total), f = Double(free)
            cached = max(0, min(100, (t - f) / t * 100))
        }
        return cached
    }
}

// MARK: - 电池

struct BatteryRead {
    var percent: Int = 0
    var external: Bool = false
    var charging: Bool = false
    var full: Bool = false
    var watts: Double = 0     // 正=充电 负=放电
    var installed: Bool = false
}

/// 读 AppleSmartBattery 一次拿全部字段；状态判定带 2 tick 滞回，避免图标在 0 W 附近抖动。
final class BatteryMonitor {
    private var pendingState: BatteryState?
    private var pendingCount = 0
    private(set) var state: BatteryState = .unplugged
    private(set) var last = BatteryRead()

    func sample() -> BatteryRead {
        var r = BatteryRead()
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else {
            last = r
            return r
        }
        defer { IOObjectRelease(svc) }

        func int(_ key: String) -> Int? {
            guard let v = IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() else { return nil }
            return (v as? NSNumber)?.intValue
        }

        r.installed = (int("BatteryInstalled") ?? 0) != 0
        let cur = int("CurrentCapacity") ?? 0
        let maxC = int("MaxCapacity") ?? 100
        r.percent = maxC > 0 ? min(100, Int((Double(cur) / Double(maxC) * 100).rounded())) : 0
        r.external = (int("ExternalConnected") ?? 0) != 0
        r.charging = (int("IsCharging") ?? 0) != 0
        r.full = (int("FullyCharged") ?? 0) != 0
        if let amp = int("InstantAmperage"), let mv = int("Voltage") {
            r.watts = Double(amp) * Double(mv) / 1_000_000
        }

        let next = decide(r)
        if next == state {
            pendingCount = 0
            pendingState = nil
        } else if pendingState == next {
            pendingCount += 1
            if pendingCount >= 2 { state = next; pendingState = nil; pendingCount = 0 }
        } else {
            pendingState = next
            pendingCount = 0
        }
        last = r
        return r
    }

    private func decide(_ r: BatteryRead) -> BatteryState {
        if !r.external { return .unplugged }
        if r.charging { return .charging }
        if r.full { return .pause }
        if r.watts < -0.5 { return .discharging }
        return .pause
    }
}

// MARK: - 进程

struct ProcSample {
    /// 代表进程：组内内存最大的那个，只用来取图标（同一 app 的图标相同）。
    let pid: Int32
    let name: String
    let cpuPercent: Double
    /// 进程内存（bytes），口径由「设置 → 进程内存口径」决定：
    /// - `.footprint` → `ri_phys_footprint`（活动监视器「内存」列同源，含压缩页与映射）
    /// - `.rss`       → `ri_resident_size`（与 `ps` / `top` 的 RSS 逐进程完全相等）
    ///
    /// 两个字段在同一次 `proc_pid_rusage(RUSAGE_INFO_V4)` 的返回结构里，换口径只换读哪个字段，
    /// **不增加 syscall**：实测 565 进程一轮 0.85 ms → 0.84 ms（噪声内）。
    /// 若改成外挂 `/usr/bin/footprint` 取同一数字，单进程 148 ms，全量约 71 s/轮——不可行。
    ///
    /// v3.4.3 起：同一 `.app` 下的全部进程已合并为一条，本字段是**组内合计**。
    let memoryBytes: Double
    /// 组内进程数；无 `.app` 归属的系统进程为 1。
    var processCount: Int = 1
}

/// libproc 两次采样算 CPU 差值。读不到的进程（约 38%）直接跳过，不用 root 绕过。
///
/// v3.2 修正一个 41.67× 的量纲错误：`rusage_info_v4.ri_user_time` / `ri_system_time`
/// 的单位是 **Mach absolute ticks**，不是纳秒。旧代码直接 `/1e9`，在 M1
/// （timebase 125/3，1 tick = 41.67 ns）上把每个进程的 CPU 都低估 41.67 倍，
/// 于是系统进程显示 31.5% 时这里只有 0.9%，按这个错误值排序
/// 得到的 Top 5 也完全不是同一批进程。
///
/// 本机实证（单线程 busy loop 满跑 1.000 s）：
///   rusage 差值 23,765,608；直接 /1e9 = 0.0238 s（2.38%）；
///   × 125/3 /1e9 = 0.9902 s（99.02%）——只有后者符合「跑满一核」。
final class ProcessSampler {
    /// `start` 是进程启动时刻（mach ticks），用作 pid 复用的身份校验：
    /// pid 会被系统回收再分配给新进程，只按 pid 缓存路径会把「新进程」认成「旧 app」。
    private struct Tick { var cpuTicks: UInt64; var start: UInt64; var rss: UInt64; var footprint: UInt64 }
    private struct GroupEntry { var start: UInt64; var group: String? }

    /// Mach ticks → 纳秒。整个进程生命周期内 timebase 不变，启动时算一次即可。
    private let nsPerTick: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return tb.denom > 0 ? Double(tb.numer) / Double(tb.denom) : 1
    }()

    private var last: [Int32: Tick] = [:]
    private var lastAt = Date()
    /// pid → (启动时刻, 归属 app 名)。`proc_pidpath` 1.65 µs/次，只在 pid 或其启动时刻变化时重算；
    /// 命中缓存时整轮归组成本约 0.05 ms（实测 370 个可读进程）。
    private var groupCache: [Int32: GroupEntry] = [:]

    private func pids() -> [Int32] {
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard bytes > 0 else { return [] }
        let count = Int(bytes) / MemoryLayout<Int32>.size + 32
        var buf = [Int32](repeating: 0, count: count)
        let got = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &buf, Int32(count * MemoryLayout<Int32>.size))
        guard got > 0 else { return [] }
        return buf.prefix(Int(got) / MemoryLayout<Int32>.size).filter { $0 > 0 }
    }

    private func name(of pid: Int32) -> String? {
        var bsd = proc_bsdinfo()
        let sz = Int32(MemoryLayout<proc_bsdinfo>.size)
        let r = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, sz)
        guard r == sz else { return nil }
        let s = withUnsafeBytes(of: bsd.pbi_name) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        if !s.isEmpty { return s }
        let c = withUnsafeBytes(of: bsd.pbi_comm) { raw -> String in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return c.isEmpty ? nil : c
    }

    private func rusage(_ pid: Int32) -> Tick? {
        var info = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &info) { p -> Bool in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rp in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rp) == 0
            }
        }
        guard ok else { return nil }
        return Tick(cpuTicks: info.ri_user_time &+ info.ri_system_time,
                    start: info.ri_proc_start_abstime,
                    rss: info.ri_resident_size,
                    footprint: info.ri_phys_footprint)
    }

    /// 进程归属的 app 名（`.../Some App.app/...` → `Some App`）。
    /// 取路径里**第一个** `.app/` 之前的部分：helper 常自带 `.app` 套在母 app 里，
    /// 第一个命中才是用户认知里的那个应用。
    private func appName(pid: Int32, start: UInt64) -> String? {
        if let e = groupCache[pid], e.start == start { return e.group }
        var name: String? = nil
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buf, 4096)
        if n > 0 {
            let path = String(decoding: buf.prefix { $0 != 0 }, as: UTF8.self)
            if let r = path.range(of: ".app/") {
                let stem = String(path[path.startIndex..<r.lowerBound])
                let base = (stem as NSString).lastPathComponent
                if !base.isEmpty { name = base }
            }
        }
        groupCache[pid] = GroupEntry(start: start, group: name)
        return name
    }

    func sample() -> [ProcSample] {
        let now = Date()
        let dt = max(now.timeIntervalSince(lastAt), 0.001)
        // 每轮读一次口径：改设置后最迟下一轮（≤2 s）生效，不必重启。
        let metric = Prefs.shared.memMetric
        var fresh: [Int32: Tick] = [:]

        // 归组：同一 `.app` 的进程合成一行（内存、CPU 各自求和）；
        // 没有 `.app` 归属的系统守护进程保持单行。
        struct Agg { var mem = 0.0; var cpu = 0.0; var count = 0; var repPid: Int32 = 0; var repMem = -1.0 }
        var groups: [String: Agg] = [:]
        var out: [ProcSample] = []

        for pid in pids() {
            guard let t = rusage(pid) else { continue }
            fresh[pid] = t
            guard let prev = last[pid], t.cpuTicks >= prev.cpuTicks, let nm = name(of: pid) else { continue }
            let cpu = Double(t.cpuTicks - prev.cpuTicks) * nsPerTick / 1e9 / dt * 100
            let mem = metric == .rss ? t.rss : t.footprint
            // v3.4.3：不再用 `cpu > 0.05` 过滤。那个过滤是为「按 CPU 取前五」服务的，
            // 但它同时把**空闲的大内存进程**丢掉了（实测单轮丢 159 个 / 986 MB / 26%），
            // 于是「按内存排序」拿到的其实只是「忙进程里的内存前五」——排序口径与数据源口径不一致。
            // 现在保留全部可读进程，排序只在渲染前对内存里的数组做一次，成本可忽略。
            guard mem > 0 else { continue }

            if let app = appName(pid: pid, start: t.start) {
                var a = groups[app] ?? Agg()
                a.mem += Double(mem)
                a.cpu += cpu
                a.count += 1
                if Double(mem) > a.repMem { a.repMem = Double(mem); a.repPid = pid }
                groups[app] = a
            } else {
                out.append(ProcSample(pid: pid, name: nm, cpuPercent: cpu, memoryBytes: Double(mem)))
            }
        }

        for (app, a) in groups {
            out.append(ProcSample(pid: a.repPid, name: app, cpuPercent: a.cpu,
                                  memoryBytes: a.mem, processCount: a.count))
        }

        last = fresh
        lastAt = now
        // 顺手回收已退出 pid 的缓存，避免长跑无限增长。
        if groupCache.count > fresh.count {
            groupCache = groupCache.filter { fresh[$0.key] != nil }
        }
        return out.sorted { $0.cpuPercent > $1.cpuPercent }
    }
}

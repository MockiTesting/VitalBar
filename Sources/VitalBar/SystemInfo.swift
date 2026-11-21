// SPDX-License-Identifier: MIT

import AppKit
import Darwin
import SwiftUI

/// 弹框需要的静态/低频信息：机型、内存、系统版本、运行时长、磁盘。
struct SystemInfo {
    let chip: String
    let memoryGB: String
    let osVersion: String
    let uptime: String
    let diskTotal: Double
    let diskFree: Double
    let loadAverage: Double

    /// 离屏渲染用：把内存总量固定成 mock 值。真实读数来自 `ProcessInfo.physicalMemory`，
    /// 而 `--dump-ui` 出的图会进 README，不该反映开发者本机的实际配置。
    var memoryTotalOverride: Double?

    var memoryTotal: Double {
        memoryTotalOverride ?? Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
    }

    var diskUsedPercent: Double {
        guard diskTotal > 0 else { return 0 }
        return max(0, min(100, (diskTotal - diskFree) / diskTotal * 100))
    }

    var diskTotalGB: Double { diskTotal / 1_073_741_824 }
    var diskFreeGB: Double { diskFree / 1_073_741_824 }

    /// 5 秒缓存：`read()` 里有 sysctl + 两次卷资源查询，弹框每秒重建视图时不该重复做。
    /// 只在主线程调用（弹框 body），所以不加锁。
    private static var cache: (at: Date, info: SystemInfo)?
    private static var cachedAt = Date.distantPast

    static func read() -> SystemInfo {
        if Date().timeIntervalSince(cachedAt) < 5, let c = cache { return c.info }
        let info = compute()
        cache = (Date(), info)
        cachedAt = Date()
        return info
    }

    private static func compute() -> SystemInfo {
        let chip = shortChip()
        let mem = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let up = ProcessInfo.processInfo.systemUptime
        let days = Int(up) / 86400
        let hours = (Int(up) % 86400) / 3600
        let mins = (Int(up) % 3600) / 60

        var total: Double = 0, free: Double = 0
        let url = URL(fileURLWithPath: NSHomeDirectory())
        if let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]) {
            total = Double(v.volumeTotalCapacity ?? 0)
            free = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
        }

        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)

        return SystemInfo(chip: chip,
                          memoryGB: String(format: "%.1f GB", mem.rounded()),
                          osVersion: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                          uptime: days > 0 ? "已运行 \(days)天\(hours)小时" : "已运行 \(hours)小时\(mins)分",
                          diskTotal: total,
                          diskFree: free,
                          loadAverage: loads[0])
    }

    /// 顶部信息条的芯片名只放得下 2~7 个字符（如 `M1`、`M2 Pro`）。
    /// `Apple Silicon` / `MacBookAir10,1` 这类全名会被 Chip 截成 `Apple Sili…`，
    /// 所以一律压成营销短名：优先读 `machdep.cpu.brand_string`（Apple Silicon
    /// 上是 `Apple M1` / `Apple M2 Pro`），取不到再按 `hw.model` 前缀兜底。
    private static func shortChip() -> String {
        func sysctlString(_ key: String) -> String? {
            var size = 0
            guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0 else { return nil }
            var buf = [CChar](repeating: 0, count: size)
            guard sysctlbyname(key, &buf, &size, nil, 0) == 0 else { return nil }
            return String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }

        if let brand = sysctlString("machdep.cpu.brand_string"),
           let r = brand.range(of: #"M[1-9][0-9]?(\s+(Pro|Max|Ultra))?"#, options: .regularExpression) {
            return String(brand[r])
        }
        let model = sysctlString("hw.model") ?? ""
        // 机型标识符 → 芯片系列。只列会影响这一行长度的分族，其余退回 `Mac`。
        let families: [(String, String)] = [
            ("MacBookAir10", "M1"), ("MacBookPro17", "M1"), ("Macmini9", "M1"),
            ("MacBookPro18", "M1 Pro"), ("Mac13", "M1"), ("iMac21", "M1"),
            ("Mac14", "M2"), ("Mac15", "M3"), ("Mac16", "M4"),
        ]
        for (prefix, name) in families where model.hasPrefix(prefix) { return name }
        return "Mac"
    }
}

/// 温度：SMC 的平均值，读不到就返回 nil（界面显示「—」，绝不把缺失当成 0）。
///
/// v3.2 从「写死 22 个键」改成**一次性自动发现**。M1 上 GPU 温度键并不叫
/// `Tg05/Tg0D/...`，旧表整族读不到，GPU 卡片右上角的温度胶囊长期空白。
/// 现在扫一遍 SMC 的 `#KEY`，按前缀给 T* 传感器分类：
/// `Tg*` → GPU，`Te*`/`TC*`/`Tc*`/`Tp*` → CPU，只保留读数落在 10…105°C 的键。
/// 发现结果常驻，之后每 2 秒只读十几个已确认的键。
final class SensorReader {
    static let shared = SensorReader()
    private let smc = SMC.shared
    private var lastAt = Date.distantPast
    private var cached: (cpu: Double?, gpu: Double?) = (nil, nil)
    private var discoveredCPU: [String]?
    private var discoveredGPU: [String]?

    /// 发现失败时的兜底（Intel / 老机型的常见键名）。
    private let fallbackCPUKeys = ["Tc0a", "Tc0b", "Tc7a", "Tc7b", "Tc8a", "Tc8b", "Tc9a", "Tc9b",
                                   "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X"]
    private let fallbackGPUKeys = ["Tg05", "Tg0D", "Tg0L", "Tg0T", "Tg0a", "Tg0b"]

    /// 2 秒一读：温度是缓变量，1 Hz 读十几个键纯属浪费
    func temps() -> (cpu: Double?, gpu: Double?) {
        if Date().timeIntervalSince(lastAt) < 2 { return cached }
        lastAt = Date()
        discoverIfNeeded()

        func avg(_ list: [String]) -> Double? {
            let vals = list.compactMap { smc.double($0) }.filter { $0 >= 10 && $0 <= 105 }
            guard !vals.isEmpty else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }
        cached = (avg(discoveredCPU ?? []), avg(discoveredGPU ?? []))
        return cached
    }

    private func discoverIfNeeded() {
        guard discoveredCPU == nil else { return }
        var cpu: [String] = [], gpu: [String] = []
        for key in smc.allKeys() where key.hasPrefix("T") {
            guard let v = smc.double(key), v >= 10, v <= 105 else { continue }
            if key.hasPrefix("Tg") { gpu.append(key) }
            else if key.hasPrefix("Te") || key.hasPrefix("TC")
                        || key.hasPrefix("Tc") || key.hasPrefix("Tp") { cpu.append(key) }
        }
        discoveredCPU = cpu.isEmpty ? fallbackCPUKeys : cpu
        discoveredGPU = gpu.isEmpty ? fallbackGPUKeys : gpu
    }
}

/// 内存压力 = (wired + compressed) / 物理内存，与活动监视器同口径。
/// 不是内存占用率：被缓存占用的页是可回收的，不该算进「压力」。
/// 弹框内存行副标题里的「压力 N%」就是这个值。
enum MemoryPressure {
    static func percent() -> Int {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        var stats = vm_statistics64_data_t()
        let kr = withUnsafeMutablePointer(to: &stats) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let hard = (Double(stats.wire_count) + Double(stats.compressor_page_count)) * Double(vm_page_size)
        var total: UInt64 = 0
        var tSize = MemoryLayout<UInt64>.size
        guard sysctlbyname("hw.memsize", &total, &tSize, nil, 0) == 0, total > 0 else { return 0 }
        return min(100, max(0, Int((hard / Double(total) * 100).rounded())))
    }

    /// ≥80 红、≥60 橙、其余绿。
    static func tint(_ p: Int) -> Color {
        if p >= 80 { return ThemeColor.alert }
        if p >= 60 { return ThemeColor.warn }
        return ThemeColor.ok
    }
}

/// GPU 占用率：IOAccelerator 的 PerformanceStatistics，Apple Silicon 与 Intel 同一个键。
final class GPUReader {
    private var lastAt = Date.distantPast
    private var cached: Double?

    func utilization() -> Double? {
        if Date().timeIntervalSince(lastAt) < 2 { return cached }
        lastAt = Date()
        cached = read()
        return cached
    }

    private func read() -> Double? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iter) }
        while true {
            let entry = IOIteratorNext(iter)
            guard entry != 0 else { break }
            defer { IOObjectRelease(entry) }
            guard let ref = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString,
                                                            kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let props = ref as? [String: Any] else { continue }
            if let v = props["Device Utilization %"] as? Int { return Double(v) }
            if let v = props["Device Utilization %"] as? Double { return v }
        }
        return nil
    }
}

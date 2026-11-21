// SPDX-License-Identifier: MIT

import Foundation
import IOKit
import IOKit.ps

/// 用户态读 AppleSMC（不需要 root）。
///
/// 结构体布局必须与内核期望的逐字节一致——字段顺序、`padding`、`bytes` 元组都不能动，
/// 否则每次读回都是 0 或垃圾值。
final class SMC {
    static let shared = SMC()

    private var conn: io_connect_t = 0
    private let ioLock = NSLock()
    private(set) var available = false

    private struct KeyData {
        typealias Bytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                           UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        struct Vers { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
        struct Limit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
        struct Info { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0 }
        var key: UInt32 = 0
        var vers = Vers()
        var limit = Limit()
        var info = Info()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: Bytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }

    private init() {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { return }
        defer { IOObjectRelease(svc) }
        var c: io_connect_t = 0
        guard IOServiceOpen(svc, mach_task_self_, 0, &c) == kIOReturnSuccess else { return }
        conn = c
        available = true
    }

    private static func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }

    private static func typeStr(_ t: UInt32) -> String {
        String(UnicodeScalar(t >> 24 & 0xff)!) + String(UnicodeScalar(t >> 16 & 0xff)!)
            + String(UnicodeScalar(t >> 8 & 0xff)!) + String(UnicodeScalar(t & 0xff)!)
    }

    private func call(_ input: inout KeyData, _ output: inout KeyData) -> kern_return_t {
        var outSize = MemoryLayout<KeyData>.stride
        return IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<KeyData>.stride, &output, &outSize)
    }

    private func readRaw(_ key: String) -> (type: String, bytes: [UInt8])? {
        guard available else { return nil }
        ioLock.lock()
        defer { ioLock.unlock() }
        var input = KeyData(); input.key = Self.fourCC(key); input.data8 = 9
        var output = KeyData()
        guard call(&input, &output) == kIOReturnSuccess else { return nil }
        let size = Int(output.info.dataSize)
        guard size > 0 else { return nil }
        let type = Self.typeStr(output.info.dataType)
        input.info.dataSize = output.info.dataSize
        input.data8 = 5
        guard call(&input, &output) == kIOReturnSuccess else { return nil }
        var arr = [UInt8](repeating: 0, count: 32)
        withUnsafeBytes(of: output.bytes) { buf in for i in 0..<min(size, 32) { arr[i] = buf[i] } }
        return (type, Array(arr.prefix(max(size, 4))))
    }

    /// 通用数值解码。`ui16` 走**大端**——这是传感器键（温度等）的约定，别为了功率键改它。
    func double(_ key: String) -> Double? {
        guard let r = readRaw(key) else { return nil }
        let b = r.bytes
        switch r.type {
        case "flt ": return Double(b.prefix(4).withUnsafeBytes { $0.loadUnaligned(as: Float.self) })
        case "ui8 ": return Double(b[0])
        case "ui16": return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32": return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        case "fpe2": return Double((Int(b[0]) << 6) + (Int(b[1]) >> 2))
        case "sp78": return Double(Int(Int8(bitPattern: b[0])) * 256 + Int(b[1])) / 256
        default:     return nil
        }
    }

    /// 功率键（`B0AV`/`B0AC`）是唯一走**小端 + 千分位**的一组：mV / mA。
    /// 用上面的通用解码读 `B0AV` 会得到 54831 而不是 12246。`si16` 有符号，放电时为负。
    func powerValue(_ key: String) -> Double? {
        guard let r = readRaw(key) else { return nil }
        return Self.decodePowerValue(type: r.type, bytes: r.bytes)
    }

    /// 枚举键名：只用于一次性发现传感器（例如找出本机到底有哪些 T* 温度键）。
    private func keyAt(_ index: Int) -> String? {
        ioLock.lock()
        defer { ioLock.unlock() }
        var input = KeyData(); input.data8 = 8; input.data32 = UInt32(index)
        var output = KeyData()
        guard call(&input, &output) == kIOReturnSuccess else { return nil }
        let k = output.key
        guard k != 0 else { return nil }
        return Self.typeStr(k)
    }

    func allKeys() -> [String] {
        guard available, let count = double("#KEY") else { return [] }
        return (0..<Int(count)).compactMap { keyAt($0) }
    }

    static func decodePowerValue(type: String, bytes: [UInt8]) -> Double? {
        guard bytes.count >= 2 else { return nil }
        let raw = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
        switch type {
        case "ui16": return Double(raw)
        case "si16": return Double(Int16(bitPattern: raw))
        default:     return nil
        }
    }
}

/// 功率分流的一帧。
///
/// 除 `systemWatts` 外都是实测值：适配器与电池的电压/电流来自 SMC，充放电状态来自电池服务，
/// 适配器额定功率与协商档位来自 IOPS。`system` 是唯一的推导量，且与同帧数据一起算，
/// 所以界面上三个数字永远自洽。
struct PowerSample {
    var adapterVolts: Double?
    var adapterAmps: Double?
    var batteryVolts: Double?
    var batteryAmps: Double?
    var adapterWatts: Double?
    var batteryWatts: Double?
    var systemWatts: Double?
    var percent: Int?
    var isCharging = false
    var externalConnected = false
    var realtimeAvailable = true
    var ratedWatts: Double?
    var adapterProtocol: String?
    var profileVolts: Double?
    var profileAmps: Double?
    var externalLimit: Int?
    var externalLowerDelta: Int?

    /// `系统 = 适配器 − 电池`。充电中的电池是负载（+W），放电中的电池是电源（−W），
    /// 停在 0 W 两头都不是——所以是相减，不是求和。
    static func system(adapter: Double?, battery: Double?) -> Double? {
        guard let a = adapter, let b = battery else { return nil }
        return a - b
    }

    var headroomWatts: Double? {
        guard let rated = ratedWatts, let s = systemWatts else { return nil }
        return rated - s
    }

    /// 系统功耗占适配器额定功率的比例。功率分流里的「负载 49%」就是这个：
    /// 10.8 W ÷ 22 W = 49%，不是 CPU 负载、也不是 load average。
    /// 铭牌或实时功率任一缺失就返回 nil，界面留空而不编造数字。
    var loadFraction: Double? {
        guard let rated = ratedWatts, rated > 0, let s = systemWatts, s > 0 else { return nil }
        return s / rated
    }

    enum ChargeState { case charging, holding, unplugged, unknown }

    var chargeState: ChargeState {
        if !externalConnected { return realtimeAvailable ? .unplugged : .unknown }
        return isCharging ? .charging : .holding
    }
}

/// 1 Hz 读四个功率键 + 慢字段（状态 2 s、充电器规格 5 s、外部策略 60 s）。
/// 只读：不写 SMC、不写电池服务、不改充电策略。必须单队列调用（内部有可变缓存、无锁）。
final class PowerReader {
    static let shared = PowerReader()

    private let smc = SMC.shared
    private var stateAt = Date.distantPast
    private var percent: Int?
    private var charging = false
    private var external = false

    private var specAt = Date.distantPast
    private var rated: Double?
    private var specProtocol: String?
    private var profileVolts: Double?
    private var profileAmps: Double?

    private var policyAt = Date.distantPast
    private var externalLimit: Int?
    private var externalLowerDelta: Int?

    /// V 与 A 分开做轻 EMA，保证 W 是界面上那两个数字的乘积。原始键逐 tick 抖 ±0.1 A。
    private var ema: [String: Double] = [:]
    private let alpha = 0.35

    func read(now: Date = Date()) -> PowerSample {
        var s = PowerSample()
        refreshState(now: now)
        refreshSpec(now: now)
        refreshPolicy(now: now)

        let rawBatV = smc.powerValue("B0AV").map { $0 / 1000 }
        let rawBatA = smc.powerValue("B0AC").map { $0 / 1000 }
        let rawAdV = smc.double("VD0R")
        let rawAdA = smc.double("ID0R")

        s.batteryVolts = smooth("bv", rawBatV)
        s.batteryAmps = smooth("ba", rawBatA)
        s.adapterVolts = smooth("av", rawAdV)
        s.adapterAmps = smooth("aa", rawAdA)
        s.realtimeAvailable = rawBatV != nil || rawBatA != nil || rawAdV != nil || rawAdA != nil

        s.adapterWatts = product(s.adapterVolts, s.adapterAmps)
        s.batteryWatts = product(s.batteryVolts, s.batteryAmps)
        // 没插电时 DC 侧没有读数，"没有适配器"是事实而不是缺测：报 0，让 system 仍可算。
        if !external, s.realtimeAvailable { s.adapterWatts = 0 }
        s.systemWatts = PowerSample.system(adapter: s.adapterWatts, battery: s.batteryWatts)

        s.percent = percent
        s.isCharging = charging
        s.externalConnected = external
        s.ratedWatts = rated
        s.adapterProtocol = specProtocol
        s.profileVolts = profileVolts
        s.profileAmps = profileAmps
        s.externalLimit = externalLimit
        s.externalLowerDelta = externalLowerDelta
        return s
    }

    private func product(_ a: Double?, _ b: Double?) -> Double? {
        guard let a, let b else { return nil }
        return a * b
    }

    private func smooth(_ key: String, _ value: Double?) -> Double? {
        guard let value else { ema[key] = nil; return nil }
        let next = ema[key].map { $0 + (value - $0) * alpha } ?? value
        ema[key] = next
        return next
    }

    private func refreshState(now: Date) {
        guard now.timeIntervalSince(stateAt) >= 2 else { return }
        stateAt = now
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard svc != 0 else { return }
        defer { IOObjectRelease(svc) }
        func int(_ key: String) -> Int? {
            guard let ref = IORegistryEntryCreateCFProperty(svc, key as CFString, kCFAllocatorDefault, 0)
            else { return nil }
            return (ref.takeRetainedValue() as? NSNumber)?.intValue
        }
        if let cc = int("CurrentCapacity") { percent = min(100, max(0, cc)) }
        charging = (int("IsCharging") ?? 0) != 0
        external = (int("ExternalConnected") ?? 0) != 0
    }

    private func refreshSpec(now: Date) {
        guard now.timeIntervalSince(specAt) >= 5 else { return }
        specAt = now
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]
        else {
            rated = nil; specProtocol = nil; profileVolts = nil; profileAmps = nil
            return
        }
        rated = (details["Watts"] as? NSNumber)?.doubleValue
        if let menu = details["UsbHvcMenu"] as? [[String: Any]], !menu.isEmpty {
            specProtocol = "USB-C PD"
            let index = (details["UsbHvcHvcIndex"] as? NSNumber)?.intValue
            let entry = menu.first { ($0["Index"] as? NSNumber)?.intValue == index } ?? menu.last
            if let v = (entry?["MaxVoltage"] as? NSNumber)?.doubleValue,
               let a = (entry?["MaxCurrent"] as? NSNumber)?.doubleValue {
                profileVolts = v / 1000
                profileAmps = a / 1000
            }
        } else if (details["IsWireless"] as? NSNumber)?.intValue == 1 {
            specProtocol = "Wireless"
        } else {
            specProtocol = "AC"
        }
    }

    /// 本机充电管理策略，只读来"解释"保持状态，绝不修改。文件不存在 = 没有外部策略，不是错误。
    private func refreshPolicy(now: Date) {
        guard now.timeIntervalSince(policyAt) >= 60 else { return }
        policyAt = now
        guard let data = FileManager.default.contents(atPath: "/etc/batt.json"),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            externalLimit = nil; externalLowerDelta = nil
            return
        }
        externalLimit = (obj["limit"] as? NSNumber)?.intValue
        externalLowerDelta = (obj["lowerLimitDelta"] as? NSNumber)?.intValue
    }
}

/// 本机传感器自检：`VitalBar --smc` 列出所有能读到的温度键与数值。
///
/// 温度键位随机型变化，排查「某台机器上温度不显示」时先跑这一条，
/// 确认是键名没被探测到，还是数值本身越界。
enum SMCDump {
    static func run() {
        let smc = SMC.shared
        let keys = smc.allKeys()
        print("keys=\(keys.count)")
        for k in keys.sorted() where k.hasPrefix("T") {
            if let v = smc.double(k), v > 0, v < 130 {
                print("\(k) = \(String(format: "%.2f", v))")
            }
        }
    }
}

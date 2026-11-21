// SPDX-License-Identifier: MIT

import Foundation

/// 本机 `log` 命令在受限环境下不可用，调试信息直接落文件。
///
/// 默认关闭，只有设了 `vitalbar.debugLog` 才真正写盘——否则每秒一 tick 的日志
/// 会把文件写到几百 KB，纯属浪费。
enum Dbg {
    static let path = "/tmp/vitalbar.log"

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "vitalbar.debugLog") }

    static func log(_ s: String) {
        guard enabled else { return }
        let line = "\(Date().timeIntervalSince1970) \(s)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile()
            h.write(data)
            h.closeFile()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

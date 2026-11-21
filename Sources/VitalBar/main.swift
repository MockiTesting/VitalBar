// SPDX-License-Identifier: MIT

import AppKit

// 离屏渲染模式：不进事件循环，出 PNG 后退出
if let i = CommandLine.arguments.firstIndex(of: "--dump") {
    let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "/tmp/vitalbar-dump"
    RenderDump.run(dir: dir)
    exit(0)
}

// 弹框离屏渲染（五态 × 浅深 × 1×/2×）
if let i = CommandLine.arguments.firstIndex(of: "--dump-ui") {
    let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "/tmp/vitalbar-ui"
    RenderDump.dumpUI(dir: dir)
    exit(0)
}

// 菜单栏条带（浅 / 深各一张，只含本应用状态项，可直接进 README）
if let i = CommandLine.arguments.firstIndex(of: "--dump-menubar") {
    let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "/tmp/vitalbar-menubar"
    RenderDump.dumpMenubar(dir: dir)
    exit(0)
}

// 行描边不透明度对比（三档 × 浅深，1 绿 2 黄 1 红）
if let i = CommandLine.arguments.firstIndex(of: "--dump-outline") {
    let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "/tmp/vitalbar-outline"
    RenderDump.dumpOutline(dir: dir)
    exit(0)
}

if CommandLine.arguments.contains("--smc") {
    SMCDump.run()
    exit(0)
}

// 登录项自检（本机脚本可验证，不必点 UI）：--login [status|on|off]
if let i = CommandLine.arguments.firstIndex(of: "--login") {
    let action = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "status"
    if action == "on" || action == "off" {
        if let err = LoginItem.set(action == "on") {
            print("失败：\(err)")
            exit(1)
        }
    }
    print("bundle = \(Bundle.main.bundlePath)")
    print("inApplications = \(LoginItem.runsFromApplications)")
    print("status = \(LoginItem.statusDescription)")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

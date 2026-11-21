# VitalBar

macOS 菜单栏系统监控工具。常驻菜单栏显示 CPU、内存、GPU、磁盘占用与电池状态，点击展开面板查看四项指标的实时读数、功率分流与主要进程。纯 Swift + SwiftUI/AppKit 实现，无第三方依赖，无后台守护进程，不使用网络。

## 下载

下载页：[Releases](https://github.com/MockiTesting/VitalBar/releases)。提供 arm64 + x86_64 通用二进制，要求 macOS 13 或更高版本。

1. 解压 `VitalBar-<版本>-macos-universal.zip`，把 `VitalBar.app` 拖进「应用程序」。
2. 首次打开会被 Gatekeeper 拦下（分发包是 ad-hoc 签名、未经 Apple 公证）。到「系统设置 → 隐私与安全性」点「仍要打开」，或先执行 `xattr -d com.apple.quarantine /Applications/VitalBar.app` 再打开。
3. 打开后到设置页顶部开启「登录时启动」，之后随登录自动运行。

上述拦截只影响首次启动；如果不放心，可以按下一节自行从源码构建。

## 功能

**菜单栏**

- 两枚指标槽位，可各自选择 CPU / 内存 / GPU / 磁盘，也可留空只显示图标。
- 三种显示方式：仅图标、仅实时数据、图标 + 数据；两种排列：分栏（左右并排）与堆叠（每指标一行）。
- 电池：纯矢量绘制的四态字形——充电（插头 + 加号）、充电暂停（插头 + 双竖条）、接电放电（插头 + 横杠）、电池供电（无插头 + 短横），可叠加电量百分比。
- 可选显示实时上传 / 下载速率。

**面板**

- 四行指标（CPU / GPU / 内存 / 磁盘）：电平条、副标题（温度、负载、已用容量、内存压力）与整数读数；跨过告警阈值时只染数值、电平条尾段与行描边，图标恒为身份色。
- 功率分流：适配器电压 / 电流、USB-C PD 档位、系统负载、电池充放功率、充电上限策略与余量；数据不可用时退化为文字说明，不伪造数值。
- 主要进程：按应用合并同一 App 的全部子进程（含 helper），一行显示该应用的内存与 CPU 合计，悬停可见进程数；默认按内存排序。

**设置**

外观（跟随系统 / 浅色 / 深色）、显示方式、数据排列、实时网速、电池状态与百分比、两枚指标槽位、进程内存口径、登录时启动。

## 系统要求

- macOS 13 或更高版本。
- Apple Silicon 与 Intel 均可构建；温度、功率、电池相关读数依赖 IOKit / AppleSMC，不同机型可读到的传感器键不完全一致（读不到时留空，不显示 0）。

## 构建

需要 Xcode 命令行工具（Swift 5.9+）。

```bash
# 编译 → 组装 bundle → 签名 → 启动，一条命令
scripts/build.sh --run       # 从 build/VitalBar.app 启动（开发用）
scripts/build.sh --install   # 装到 /Applications 并从那里启动（日常使用）

# 出分发包：通用二进制（arm64 + x86_64）并压成 zip，打印 SHA-256
scripts/build.sh --universal --zip
```

脚本依次执行：`swift build` → 复制二进制与资源进 bundle → ad-hoc 签名（`codesign --sign -`）→ 启动。`--install` 额外做 `ditto` 安装、注销 `build/` 副本的 LaunchServices 记录，避免同一 bundle id 出现两份。`--zip` 用 `ditto -c -k --keepParent` 打包，保住签名依赖的扩展属性，解压后直接得到 `VitalBar.app`。

直接执行 `.build/release/VitalBar` 不可行：进程会继承终端的沙箱限制，IOKit 与 libproc 调用被拒，只能看到空数据。必须经 bundle 启动。

> 签名是 ad-hoc，仅适合本机使用。分发需替换为 Developer ID 证书并做公证，否则 Gatekeeper 会拦截。

## 命令行自检

离屏渲染与数据自检入口，便于在没有 UI 交互时核对版式：

```bash
.build/release/VitalBar --dump-ui /tmp/out   # 面板各功率状态 × 浅深 × 1×/2×、设置页浅深、电平条阶梯
.build/release/VitalBar --smc                # 列出本机可读的 AppleSMC 温度键与数值

# 登录项相关必须在 app bundle 内执行（SMAppService 依赖 bundle 身份）
build/VitalBar.app/Contents/MacOS/VitalBar --login status
build/VitalBar.app/Contents/MacOS/VitalBar --login on
```

## 实现要点

| 数据 | 来源 |
|---|---|
| CPU 占用 | `proc_pid_rusage(RUSAGE_INFO_V4)` 取进程累计 ticks，Mach timebase 换算后按采样间隔差分 |
| 内存（系统） | `host_statistics64` 的 active + wire + compressed 占物理内存比例 |
| 内存（进程） | 同一次 `proc_pid_rusage` 里的 `ri_phys_footprint`（活动监视器口径）或 `ri_resident_size`（rss 口径） |
| GPU | `IOAccelerator` 的 `PerformanceStatistics` |
| 磁盘 | 卷资源查询（总容量 / 可用容量） |
| 电池 / 功率 | `AppleSmartBattery` + AppleSMC（用户态读取，不需要 root） |
| 温度 | AppleSMC 温度键，按机型探测可用的 CPU / GPU 键 |

- 采样在后台串行队列以 2 秒节拍进行，视图只读最近一帧快照，界面不阻塞。
- 进程列表用 `proc_listpids` 枚举，归属按 `proc_pidpath` 里**第一个** `.app/` 之前的部分分组，缓存键为 `(pid, 进程启动时刻)`，避免 pid 复用导致误归组。
- 电池图标、电平条、功率分流图均为运行时绘制（Core Graphics / SwiftUI Shape），不依赖位图资源。
- 设置项存于 `UserDefaults`（键前缀 `vitalbar.`），变更即时生效；登录项走 `SMAppService.mainApp`，状态每次向系统查询，不自行缓存。

## 性能

在 Apple Silicon（M1 / 8 GB）机器、约 560 个进程的环境下实测：

- 进程采样一轮约 0.85 ms，按 2 秒节拍折算约 0.042% 单核。
- 叠加应用归组后每轮增量 0.2–0.7 ms（约 0.01–0.035% 单核）；路径缓存命中时归组本身接近零成本。
- 应用自身常驻占用：CPU 中位 0.87%，footprint 约 11 MB。
- 无空闲轮询之外的定时器，不发起网络请求。

## 目录结构

```
Sources/VitalBar/
  main.swift              入口；离屏渲染与自检命令行分支
  AppDelegate.swift       生命周期、单实例、外观应用
  StatusItemController.swift  状态项安装、面板/设置窗口管理
  MenuBarRenderer.swift   菜单栏图像合成（标签、数值、电池、网速）
  BatteryGlyph.swift      电池四态矢量字形
  PopupView.swift         面板：指标行、功率分流、主要进程
  SettingsView.swift      设置页
  Prefs.swift             偏好定义与读写
  SamplerHub.swift        2 秒采样节拍与快照缓存
  Samplers.swift          CPU / 内存 / 进程 / 电池采样
  SystemInfo.swift        机型、系统版本、温度、内存压力、GPU
  SMC.swift               AppleSMC 用户态读写
  LoginItem.swift         登录时启动（SMAppService）
  Theme.swift             颜色与排版令牌
  HUDComponents.swift     图标、电平条、分组标签等基础组件
  RenderDump.swift        离屏渲染（--dump-*）
  Dbg.swift               可选调试日志
Assets/
  Icons/                  图标源矢量
  BatteryState/           电池字形生成器与绘制规范
Resources/                Info.plist、AppIcon、菜单栏模板图
scripts/build.sh          构建 / 运行 / 安装 / 打包
```

## 已知限制

- ad-hoc 签名：每次重新编译后二进制哈希都会变，若将来申请屏幕录制、辅助功能等隐私权限，系统会视为新应用而要求重新授权（登录项不受影响）。
- 进程内存按进程各算一份共享页，全机相加会大于系统实际已用内存，属口径特性。
- 进程枚举只能读取当前用户有权限的进程；系统守护进程的部分字段可能不可读，此时该进程不会出现在列表中。
- 温度与功率依赖机型 SMC 键位，非 Apple Silicon 机型上可能仅有部分读数。

## 许可

[MIT](LICENSE) © 2026 MockiTesting

可自由使用、修改、分发，包括商业用途与闭源衍生，只需保留版权声明与许可声明。软件按「原样」提供，不含任何担保。

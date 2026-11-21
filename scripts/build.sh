#!/bin/bash
# 构建 VitalBar.app：swift 编译 → 组装 bundle → ad-hoc 签名。
# 用法：scripts/build.sh [--run] [--install]
#
#   --run      构建后杀掉旧实例，从仓库内的 build/ 启动（开发用）
#   --install  构建后安装到 /Applications/VitalBar.app 并从那里启动（日常使用）
#   两个都给时以 --install 为准，不会同时跑两份（Info.plist 里也禁止多实例）。
#
# 注意 `--show-bin-path` 只打印路径、**不触发编译**，必须先单独跑一次 swift build。
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
APP="build/VitalBar.app"
DO_RUN=0
DO_INSTALL=0

for arg in "$@"; do
  case "$arg" in
    --run) DO_RUN=1 ;;
    --install) DO_INSTALL=1 ;;
    *) echo "未知参数：$arg（可用：--run / --install）"; exit 1 ;;
  esac
done

swift build -c "$CONFIG" --disable-sandbox
BIN=$(swift build -c "$CONFIG" --disable-sandbox --show-bin-path)/VitalBar

# 不整目录删除：就地覆盖二进制与 plist，签名用 --force 重签。
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -f "$BIN" "$APP/Contents/MacOS/VitalBar"
cp -f Resources/Info.plist "$APP/Contents/Info.plist"
# 正式图标：bundle 图标 + 菜单栏单色 template 图（源矢量在 Assets/Icons/*.svg，
# 重新生成办法见 docs/VitalBar-plan-v2.md §12.2）
cp -f Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -f Resources/MenubarIcon.png "$APP/Contents/Resources/MenubarIcon.png"
# MIT 要求「软件的所有副本」都带版权与许可声明，分发出的 .app 也算副本，
# 所以 LICENSE 必须进 bundle 并在签名前放好（签名会 seal Resources）。
cp -f LICENSE "$APP/Contents/Resources/LICENSE"
# 电池状态字形是运行时用 CGPath 现画的（Sources/VitalBar/BatteryGlyph.swift），
# 不读任何 PNG；Assets/BatteryState 里只有生成器与设计验图，不进 bundle。
rm -rf "$APP/Contents/Resources/BatteryState"

codesign --force --deep --sign - --timestamp=none "$APP" >/dev/null
codesign --verify --deep --strict "$APP" && echo "signed ok: $APP"

LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# 装在 /Applications 才有意义：登录项（SMAppService）记的是 bundle 的绝对路径，
# 从 build/ 打开「登录时启动」，登录时起来的就是 build/ 里那一份。
if [ "$DO_INSTALL" = "1" ]; then
  DEST="/Applications/VitalBar.app"
  if [ ! -w /Applications ]; then
    echo "错误：/Applications 不可写，无法安装。请检查权限后重试。" >&2
    exit 1
  fi
  # 运行中替换 bundle 会让签名校验报 "sealed resource is missing or invalid"，先停。
  pkill -x VitalBar 2>/dev/null || true
  sleep 2
  rm -rf "$DEST"
  # 用 ditto 而不是 cp -R：保留资源分支与扩展属性，ad-hoc 签名拷完仍然有效。
  ditto "$APP" "$DEST"
  codesign --verify --deep --strict "$DEST" && echo "installed ok: $DEST"
  # 同一 bundle id 出现两份会让 `open -a VitalBar` / Spotlight 命中随机的那一份，
  # 装好之后把 build/ 里的副本从 LaunchServices 注销，系统里只留 /Applications。
  "$LSREGISTER" -u "$PWD/$APP" 2>/dev/null || true
  "$LSREGISTER" -f "$DEST" 2>/dev/null || true
  open -a "$DEST"
  echo "launched $(date +%T) from $DEST"
elif [ "$DO_RUN" = "1" ]; then
  # 必须走 open -a：直接执行二进制会继承调用方沙箱，IOKit / libproc 全被拒
  pkill -x VitalBar 2>/dev/null || true
  sleep 2
  open -a "$PWD/$APP"
  echo "launched $(date +%T) from $PWD/$APP"
fi

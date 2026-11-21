#!/bin/bash
# 构建 VitalBar.app：swift 编译 → 组装 bundle → ad-hoc 签名。
# 用法：scripts/build.sh [--run] [--install] [--universal] [--zip]
#
#   --run       构建后杀掉旧实例，从仓库内的 build/ 启动（开发用）
#   --install   构建后安装到 /Applications/VitalBar.app 并从那里启动（日常使用）
#   --universal 同时编译 arm64 与 x86_64，产出通用二进制（分发给 Intel 机器时用）
#   --zip       打包成 build/VitalBar-<版本>-macos-<架构>.zip，并打印 SHA-256
#   --run 与 --install 都给时以 --install 为准，不会同时跑两份（Info.plist 里也禁止多实例）。
#
# 注意 `--show-bin-path` 只打印路径、**不触发编译**，必须先单独跑一次 swift build。
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
APP="build/VitalBar.app"
DO_RUN=0
DO_INSTALL=0
DO_UNIVERSAL=0
DO_ZIP=0

for arg in "$@"; do
  case "$arg" in
    --run) DO_RUN=1 ;;
    --install) DO_INSTALL=1 ;;
    --universal) DO_UNIVERSAL=1 ;;
    --zip) DO_ZIP=1 ;;
    *) echo "未知参数：$arg（可用：--run / --install / --universal / --zip）"; exit 1 ;;
  esac
done

# bash 3.2 在 set -u 下展开空数组会报 unbound variable，故用字符串按需留空。
# 多架构构建的产物落在 .build/apple/Products/<Config>/，--show-bin-path 会给出该路径。
ARCH_FLAGS=""
if [ "$DO_UNIVERSAL" = "1" ]; then
  ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

# shellcheck disable=SC2086  # ARCH_FLAGS 需要按空格拆成独立参数，留空即不限制架构
swift build -c "$CONFIG" --disable-sandbox $ARCH_FLAGS
# shellcheck disable=SC2086
BIN=$(swift build -c "$CONFIG" --disable-sandbox $ARCH_FLAGS --show-bin-path)/VitalBar

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

# 分发用压缩包：ditto 而不是 zip(1)，能保住签名依赖的扩展属性与资源分支。
if [ "$DO_ZIP" = "1" ]; then
  VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
  ARCHS=$(lipo -archs "$APP/Contents/MacOS/VitalBar")
  case "$ARCHS" in
    "arm64 x86_64"|"x86_64 arm64") ARCH_LABEL=universal ;;
    *) ARCH_LABEL=$ARCHS ;;
  esac
  ZIP="build/VitalBar-$VERSION-macos-$ARCH_LABEL.zip"
  rm -f "$ZIP"
  # --keepParent：解压后是 VitalBar.app 这一层，而不是散落的 Contents/。
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
  echo "packed: $ZIP ($(du -h "$ZIP" | cut -f1 | tr -d ' '))"
  echo "sha256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
fi

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

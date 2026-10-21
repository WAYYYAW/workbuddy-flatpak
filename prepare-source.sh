#!/bin/sh
# 把已解包的 WorkBuddy 目录整理成 flatpak-builder 可用的 source 目录树。
#   $1 = 解包出的 opt/WorkBuddy 绝对路径
#   $2 = 输出目录
set -eu
SRC="$1"
OUT="$2"

# 某些环境（只读挂载 / 受限属性）不允许 chattr/chmod，统一降级为继续构建
soft() { "$@" 2>/dev/null || true; }

rm -rf "$OUT" 2>/dev/null || true
mkdir -p "$OUT"

# 1) 应用本体 → app/
#    cp -L 把符号链接实体化，避免 flatpak-builder 处理跨目录链接时出错
mkdir -p "$OUT/app"
cp -aL "$SRC/." "$OUT/app/" 2>/dev/null || cp -a "$SRC/." "$OUT/app/"

# 2) 清理不必要的体积与冲突
#    - locales 只保留中英文（Chromium 语言包）
if [ -d "$OUT/app/locales" ]; then
  cd "$OUT/app/locales"
  for f in *.pak; do
    case "$f" in
      zh-CN.pak|zh-TW.pak|en-US.pak|en-GB.pak) ;;
      *) rm -f "$f" ;;
    esac
  done
  cd - >/dev/null
fi
#    - 其它架构的预编译二进制
rm -rf "$OUT/app/resources/app.asar.unpacked/node_modules/@lydell/node-pty-linux-arm64" 2>/dev/null || true
rm -rf "$OUT/app/resources/app.asar.unpacked/node_modules/koffi/build/koffi/musl_x64" 2>/dev/null || true
rm -rf "$OUT/app/resources/app.asar.unpacked/node_modules/koffi/build/koffi/openbsd_x64" 2>/dev/null || true
rm -rf "$OUT/app/resources/app.asar.unpacked/node_modules/koffi/build/koffi/darwin_x64" 2>/dev/null || true
rm -rf "$OUT/app/resources/app.asar.unpacked/node_modules/koffi/build/koffi/darwin_arm64" 2>/dev/null || true
rm -rf "$OUT/app/resources/app.asar.unpacked/node_modules/koffi/build/koffi/win32_x64" 2>/dev/null || true
rm -rf "$OUT/app/resources/app.asar.unpacked/node_modules/koffi/build/koffi/win32_arm64" 2>/dev/null || true
rm -rf "$OUT/app/resources/app.asar.unpacked/node_modules/koffi/build/koffi/freebsd_x64" 2>/dev/null || true
#    - 开发/头文件类内容
rm -rf "$OUT/app/resources/runtime/node/include" 2>/dev/null || true

# 3) 权限归一化
soft find "$OUT/app" -type d -exec chmod 0755 {} +
soft find "$OUT/app" -type f -exec chmod 0644 {} +
# 需要可执行位的清单
for p in \
  "$OUT/app/workbuddy" \
  "$OUT/app/chrome-sandbox" \
  "$OUT/app/chrome_crashpad_handler" \
  "$OUT/app/resources/runtime/node/bin/node" \
  "$OUT/app/resources/runtime/node/bin/npm" \
  "$OUT/app/resources/runtime/node/bin/npx" \
  "$OUT/app/resources/runtime/node/bin/corepack" \
  "$OUT/app/resources/runtime/python/bin/python3" \
  "$OUT/app/resources/runtime/python/bin/python3.13" \
  "$OUT/app/resources/app.asar.unpacked/cli/vendor/ripgrep/x64-linux/rg" \
  "$OUT/app/resources/app.asar.unpacked/cli/vendor/genie-trash/linux-x64" \
  "$OUT/app/resources/app.asar.unpacked/cli/vendor/sandbox/5.6.15/sandbox-center" \
  "$OUT/app/resources/app.asar.unpacked/cli/vendor/sandbox/5.6.15/sandbox-cli" \
  "$OUT/app/resources/app.asar.unpacked/cli/vendor/sandbox/5.6.15/sandbox-cli-gc" \
  "$OUT/app/resources/app.asar.unpacked/cli/vendor/sandbox/5.6.15/wb-bridge" \
  "$OUT/app/resources/app.asar.unpacked/cli/vendor/sandbox/5.6.15/betterleaks" \
  "$OUT/app/resources/app.asar.unpacked/node_modules/@tencent/tencent-docs-ai-engine/bin/linux-x64/editor_sdk" \
  "$OUT/app/resources/app.asar.unpacked/resources/plugins/workbuddy-builtin/mcps/agently-cli/bin/agently-cli" \
  ; do
  [ -e "$p" ] && soft chmod 0755 "$p"
done

# 所有 .node / .so 保持 0644 即可（dlopen 不需要 +x）
# 但 shell 脚本形式的 CLI 需要 +x
soft find "$OUT/app/resources/app.asar.unpacked" -name '*.sh' -exec chmod 0755 {} +

echo "source 目录已生成：$OUT"
du -sh "$OUT/app" 2>/dev/null || true

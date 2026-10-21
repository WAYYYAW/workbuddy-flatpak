#!/bin/sh
# WorkBuddy 在 Flatpak 沙箱中的统一启动入口。
# GUI / CLI / daemon（ELECTRON_RUN_AS_NODE）都从这里进入，保证环境一致。
#
# Flatpak 会通过 /app/bin/workbuddy 这个包装脚本来调用，真正的应用文件在 /app/extra。
ROOT="${WORKBUDDY_ROOT:-/app/extra/WorkBuddy}"
export WORKBUDDY_ROOT="$ROOT"
export PATH="${ROOT}/resources/runtime/node/bin:${ROOT}:${PATH}"
unset LD_PRELOAD

# Electron 在 Wayland 下需要提示，否则会退回 XWayland。
export ELECTRON_OZONE_PLATFORM_HINT="${ELECTRON_OZONE_PLATFORM_HINT:-auto}"

# Flatpak 沙箱内没有 setuid 的 chrome-sandbox，Electron 的 user namespace
# 沙箱在这种环境下无法建立。渲染进程只加载本地内容 + 受信 origin，
# 因此关闭 Chromium 内层沙箱（Flatpak 的 bwrap 沙箱仍在）。
export ELECTRON_DISABLE_SANDBOX=1

exec "${ROOT}/workbuddy" "$@"

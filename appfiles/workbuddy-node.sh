#!/bin/sh
# 便捷入口：以 WorkBuddy 内置的 Node 运行时执行脚本
# 用法：flatpak run --command=workbuddy-node com.tencent.WorkBuddy script.js
ROOT="${WORKBUDDY_ROOT:-/app/extra/WorkBuddy}"
export PATH="${ROOT}/resources/runtime/node/bin:${ROOT}:${PATH}"
unset LD_PRELOAD
exec "${ROOT}/resources/runtime/node/bin/node" "$@"

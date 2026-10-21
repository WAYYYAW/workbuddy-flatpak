#!/bin/sh
# 构建 WorkBuddy 的 Flatpak（用户级 / CI 通用，无需 root）
#
#   ./build.sh            构建并导出到 ./repo
#   ./build.sh install    构建 + 安装到当前用户
#   ./build.sh run        直接启动
#   ./build.sh clean      清理中间产物
#
# 环境变量：
#   RPM                    本地 RPM 路径（存在则直接使用，不下载）
#   WORKBUDDY_RPM_URL      远程 RPM 地址（RPM 不存在时下载到这里）
#   SKIP_DEPS=1            跳过 runtime 安装检查（CI 中已手动装好时用）
#
set -eu

APP_ID="com.tencent.WorkBuddy"
HERE=$(cd "$(dirname "$0")" && pwd)
REPO="$HERE/repo"
BUILD_DIR="$HERE/.build-flatpak"
SRC_DIR="$HERE/.source"
EXTRACT_DIR="$HERE/.extract"
RV=25.08

RPM_NAME="WorkBuddy-linux-x64-rpm-5.6.2.40046327-c7b525f3.rpm"
RPM=${RPM:-$HERE/$RPM_NAME}
WORKBUDDY_RPM_URL=${WORKBUDDY_RPM_URL:-https://download.codebuddy.cn/workbuddy/saas/linux-x64-rpm/$RPM_NAME}

# 安装域：CI 容器里用系统级（与预装 runtime 一致），本地默认用户级
SCOPE=${FLATPAK_SCOPE:-user}
if [ "$SCOPE" = "system" ]; then
  FP_ARGS=""
  FLATPAK_USER_DIR=""
else
  FP_ARGS="--user"
  export FLATPAK_USER_DIR=${FLATPAK_USER_DIR:-$HOME/.local/share/flatpak}
fi

blue() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mERR\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 依赖检查
for c in flatpak flatpak-builder rpm2cpio cpio; do
  command -v "$c" >/dev/null 2>&1 || die "缺少 $c（sudo dnf install $c）"
done

# ---------------------------------------------------------------- runtime
# shellcheck disable=SC2086
if [ "${SKIP_DEPS:-0}" != "1" ]; then
  if ! flatpak remotes $FP_ARGS --columns=name 2>/dev/null | grep -qx flathub; then
    blue "添加 flathub 仓库 ($SCOPE)"
    flatpak remote-add $FP_ARGS --if-not-exists flathub \
      https://dl.flathub.org/repo/flathub.flatpakrepo
  fi

  # 任一处已安装即可复用（CI 镜像常预装在系统级）
  need() {
    ref="$1"
    if flatpak info "$ref" >/dev/null 2>&1; then
      blue "已安装(系统)：$ref"
      return 0
    fi
    if flatpak info --user "$ref" >/dev/null 2>&1; then
      blue "已安装(用户)：$ref"
      return 0
    fi
    blue "安装 runtime: $ref"
    flatpak install $FP_ARGS -y --noninteractive flathub "$ref"
  }
  need "org.freedesktop.Platform/x86_64/$RV"
  need "org.freedesktop.Sdk/x86_64/$RV"
  need "org.electronjs.Electron2.BaseApp/x86_64/$RV"
  need "org.freedesktop.Platform.Locale/x86_64/$RV"
fi

# ---------------------------------------------------------------- 取 RPM
if [ ! -f "$RPM" ]; then
  blue "下载 RPM"
  blue "  $WORKBUDDY_RPM_URL"
  mkdir -p "$(dirname "$RPM")"
  curl -fL --retry 3 --retry-delay 2 -C - -o "$RPM.part" "$WORKBUDDY_RPM_URL"
  mv "$RPM.part" "$RPM"
fi
[ -f "$RPM" ] || die "找不到 RPM"
blue "RPM: $(du -h "$RPM" | cut -f1)"

# ---------------------------------------------------------------- 解包
if [ ! -f "$EXTRACT_DIR/opt/WorkBuddy/workbuddy" ] && \
   [ ! -f "$SRC_DIR/app/workbuddy" ]; then
  blue "解包 RPM"
  mkdir -p "$EXTRACT_DIR"
  ( cd "$EXTRACT_DIR" && rpm2cpio "$RPM" | cpio -idm --quiet --no-preserve-owner )
fi

# ---------------------------------------------------------------- 源码树
if [ ! -f "$SRC_DIR/app/workbuddy" ]; then
  [ -x "$EXTRACT_DIR/opt/WorkBuddy/workbuddy" ] || die "解包结果不完整"
  blue "生成 source 目录"
  sh "$HERE/prepare-source.sh" "$EXTRACT_DIR/opt/WorkBuddy" "$SRC_DIR"
fi

# 元数据每次刷新，保证改动生效
rm -rf "$SRC_DIR/appfiles" "$SRC_DIR/metainfo" "$SRC_DIR/icons" 2>/dev/null || true
cp -a "$HERE/appfiles" "$HERE/metainfo" "$SRC_DIR/"
mkdir -p "$SRC_DIR/icons"
cp -a "$HERE/icons/workbuddy.png" "$SRC_DIR/icons/"
cp -a "$HERE/$APP_ID.desktop"     "$SRC_DIR/"
chmod 0755 "$SRC_DIR/appfiles/"*.sh 2>/dev/null || true
chmod 0755 "$SRC_DIR/app/workbuddy" "$SRC_DIR/app/chrome_crashpad_handler" 2>/dev/null || true

# ---------------------------------------------------------------- 构建
mkdir -p "$REPO"
blue "开始构建（源码约 1.7GB，视机器性能约 5-15 分钟）"
rm -rf "$BUILD_DIR"
# shellcheck disable=SC2086
flatpak-builder \
  $FP_ARGS \
  --arch=x86_64 \
  --force-clean \
  --default-branch=stable \
  --disable-rofiles-fuse \
  --install-deps-from=flathub \
  --repo="$REPO" \
  --state-dir="$HERE/.flatpak-builder" \
  "$BUILD_DIR" \
  "$HERE/$APP_ID.yaml"

blue "已导出到 $REPO"
if command -v ostree >/dev/null 2>&1; then
  blue "仓库内分支："
  ostree --repo="$REPO" refs 2>/dev/null | sed 's/^/    /' || true
fi

case "${1:-}" in
  install)
    flatpak remote-add --user --if-not-exists --no-gpg-verify \
      workbuddy-local "file://$REPO"
    flatpak remote-modify --user --no-gpg-verify workbuddy-local || true
    flatpak install --user -y --noninteractive --reinstall workbuddy-local "$APP_ID"
    blue "安装完成：flatpak run $APP_ID"
    ;;
  run)
    exec flatpak run "$APP_ID" ;;
  clean)
    rm -rf "$BUILD_DIR" "$HERE/.flatpak-builder"
    blue "已清理构建中间产物（保留 .source 与 repo）" ;;
  *)
    echo "    安装：./build.sh install"
    echo "    或   ：flatpak remote-add --user --if-not-exists --no-gpg-verify workbuddy-local file://$REPO"
    echo "          flatpak install --user workbuddy-local $APP_ID"
    ;;
esac

# WorkBuddy Flatpak

把官方 RPM 包重新打包为 Flatpak，`app-id` 为 `com.tencent.WorkBuddy`。

## 直接从 Release 安装（推荐）

从 [Releases](../../releases) 下载 `.flatpak` 后：

```bash
flatpak install --user ./WorkBuddy-5.6.2-x86_64.flatpak
flatpak run com.tencent.WorkBuddy
```

## 目录结构

```
com.tencent.WorkBuddy.yaml      # flatpak-builder 清单
com.tencent.WorkBuddy.desktop   # 桌面入口
metainfo/                       # AppStream 元数据
icons/workbuddy.png             # 512x512 图标（取自 RPM）
appfiles/workbuddy.sh           # 统一启动入口（GUI / CLI / daemon）
appfiles/workbuddy-node.sh      # 用内置 Node 运行时执行脚本
prepare-source.sh               # 从解包目录整理出 .source/
build.sh                        # 一键构建 + 安装
.github/workflows/build.yml     # CI：下载 RPM → 构建 → 冒烟测试 → 出产物
```

`.source/`（RPM 解包结果）、`build/`、`repo/` 都是构建中间产物，已在 `.gitignore` 中排除。

## 本地构建

```bash
sudo dnf install flatpak flatpak-builder rpm2cpio cpio
./build.sh install
```

`build.sh` 会完成：检查依赖 → 添加用户级 flathub → 安装
`org.freedesktop.Platform/Sdk` 与 `org.electronjs.Electron2.BaseApp` (25.08)
→ 按需下载 RPM → 构建 → 导出到 `./repo` → 安装到当前用户。

不需要 root：全部使用 `--user` 安装。

其他用法：

```bash
./build.sh            # 只构建，导出到 ./repo
./build.sh run        # 构建后启动
./build.sh clean      # 清理构建中间产物
```

可用环境变量覆盖下载源：

```bash
WORKBUDDY_RPM_URL=https://.../WorkBuddy-linux-x64-rpm-xxx.rpm ./build.sh
```

## CI

`.github/workflows/build.yml` 在 `ghcr.io/flathub-infra/flatpak-github-actions`
容器里跑，流程为：缓存/下载 RPM → 安装 25.08 runtime 与 BaseApp →
校验清单与元数据 → `flatpak-builder` 构建 → `flatpak build-bundle` 出单个
`.flatpak` → 用户级安装做文件布局冒烟测试 → 上传 artifact。

- 每次 push 到 `main` / PR：只出 artifact
- 推送 `v*` 标签或在 Actions 页面手动触发：额外创建 GitHub Release 并附上 `.flatpak`

## 设计要点

- **BaseApp = org.electronjs.Electron2.BaseApp 25.08**
  直接复用上游 Electron 运行时（Chromium / ffmpeg / SwiftShader / NSS 等），
  不必把 RPM 里的整套 Electron 再带一遍，体积与维护成本都更低。

- **应用文件放 `/app/extra/WorkBuddy`**
  `/app/extra` 不参与 ostree 差异优化，适合这个自更新频繁的应用；
  `/app/bin/workbuddy` 只是一层很薄的启动器。

- **启动器为什么必须存在**
  WorkBuddy 的 GUI、CLI（`codebuddy`）、daemon（`ELECTRON_RUN_AS_NODE=1`）
  都从同一个 Electron 二进制派生。容器内 `os.homedir()` 返回沙箱内的
  `$HOME`，因此 `~/.workbuddy` 自然映射到宿主
  `~/.var/app/com.tencent.WorkBuddy/.workbuddy`，与宿主上安装的版本配置隔离、
  互不干扰（需要共享时可把宿主 `~/.workbuddy` 软链或 bind 进去）。

- **`ELECTRON_DISABLE_SANDBOX` 的原因**
  Flatpak 沙箱内拿不到 SUID 的 `chrome-sandbox`，Electron 的 user namespace
  沙箱无法建立。应用只加载本地内容与受信 origin，且外层已有 bwrap 沙箱，
  因此关闭 Chromium 内层沙箱不会有实质安全损失。

- **文件访问**
  默认给了 `--filesystem=home`。WorkBuddy 的用途就是读写你的项目目录、
  打开附件、调用本地工具，收得太紧会显著影响可用性。若只想开放特定目录，
  用 Flatseal 把 `home` 去掉后单独加 `~/Work`、`~/Documents` 之类即可。

## 已知限制

| 场景 | 说明 |
| --- | --- |
| 系统托盘 | Flatpak 内可以显示，但取决于宿主是否提供 StatusNotifier 支持（GNOME 需装 AppIndicator 扩展） |
| 开机自启 | 需要 `systemd` user service，沙箱内无法直接注册；建议在宿主 GNOME「启动应用程序」里加 `flatpak run com.tencent.WorkBuddy` |
| 应用内自动更新 | 版本更新请重新执行 `./build.sh install`。应用自身的增量更新会把文件写进 `/app/extra`，Flatpak 重新安装会覆盖 |
| deep link (`workbuddy://`) | 已声明 `x-scheme-handler`，需要宿主桌面环境刷新 MIME 缓存后才生效 |
| 外部编辑器 / 系统文件对话框 | 走 XDG Desktop Portal，需宿主安装 portal 后端 |

# 01 · 前提与依赖

本项目不提供内核、ROM 或 root 方案，它假设你已经有一台**已 root** 的 Android 设备，并且用 [TMOE Linux](https://github.com/2lambda123/tmoe-linux) 装好了一个 Ubuntu chroot 容器。

## 环境要求

| 项目 | 要求 |
|---|---|
| Android | 11 及以上（需要无线/USB 调试仅为方便，非必需） |
| Root | KernelSU 或 Magisk（需要 `su -c`，因为 chroot 与挂载都要特权） |
| 容器 | TMOE Linux 的 **chroot** 容器，已验证 Ubuntu 24.04 / 26.04 |
| 显示 | Termux:X11（应用 + 命令行工具） |
| 架构 | arm64 |

## Termux 侧依赖

```bash
pkg install x11-repo
pkg install termux-x11-nightly
pkg install picom        # 可选：想开窗口阴影时用
```

> Termux:X11 的**应用**需要单独安装（GitHub Releases 或 F-Droid）。应用与服务端二进制最好来自同一版本，版本错配会导致 X 服务启动即崩（`std::bad_alloc`）。

## 容器创建（TMOE）

在 Termux 中运行 `tmoe`，选择：

```
Linux 容器 → chroot → Ubuntu → 26.04 LTS
```

安装完成后确认目录存在：

```bash
ls ~/.local/share/tmoe-linux/containers/chroot/
# ubuntu-resolute_arm64
```

## 容器内依赖

### 1. 桌面环境

```bash
apt update
apt install -y xfce4 dbus-x11 fonts-noto-cjk
```

### 2. Mesa 的 KGSL 版本（关键）

普通 `apt install mesa-*` 装的是标准 Mesa，它只认 DRM 设备，在这类设备上拿不到 3D。必须换成带 KGSL 后端的构建：

```bash
# 在容器内执行，版本要与发行版匹配
wget https://github.com/lfdevs/mesa-for-android-container/releases/download/\
mesa-27.0.0-devel-20261025-r1/mesa-for-android-container_27.0.0-devel-20261025-r1_ubuntu_resolute_arm64.tar.gz
tar -zxf mesa-for-android-container_*.tar.gz -C /
ldconfig
```

不同发行版的包名后缀不同（`ubuntu_noble_arm64`、`ubuntu_resolute_arm64`…），选错会因 ABI 差异出问题。

### 3. 可选：picom

```bash
apt install -y picom
```

## 验证清单

```bash
# 1) root 可用
su -c id          # uid=0

# 2) docker... 不，是 GPU 节点存在
ls -l /dev/kgsl-3d0    # 应为 crw-rw-rw-

# 3) Mesa 生效（容器内）
MESA_LOADER_DRIVER_OVERRIDE=kgsl eglinfo | grep -E "driver name|renderer"
# 期望: EGL driver name: kgsl / OpenGL renderer: FD610

# 4) X 服务可启动
termux-x11 :0 -ac &
ls $PREFIX/tmp/.X11-unix/   # 应出现 X0
```

四条都过了，再继续安装脚本。

## 目录约定

脚本默认使用以下路径，可用环境变量覆盖：

| 变量 | 默认值 |
|---|---|
| `CONTAINER` | `~/.../containers/chroot/ubuntu-*`（自动探测） |
| `DISPLAY_NUM` | `:0` |
| `DPI` | `160` |
| `BUSYBOX` | `/data/adb/ksu/bin/busybox` |
| `COMPOSITOR` | `none`（可选 `picom`） |

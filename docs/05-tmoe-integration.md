# 05 · 与 TMOE 的分工：读配置，不接管启动

[TMOE Linux](https://github.com/2lambda123/tmoe-linux) 负责**创建和配置**容器，本项目负责**启动和显示**。这条边界是刻意的。

## TMOE 帮我们配好了什么

每容器的启动脚本位于：

```
$CONTAINER/usr/local/etc/tmoe-linux/container/tmoe-linux-container
```

里面有几个我们直接沿用的配置：

| 配置 | 示例值 | 作用 |
|---|---|---|
| `CHROOT_USER` | `pad` | 登录用户（不是 root） |
| `MOUNT_TERMUX` | `true` | Termux home → 容器 `/media/termux` |
| `MOUNT_SD` | `true` | `/data/media/0/Download` → `/media/sd` |
| `wm_size.txt` | `1200x1920` | 窗口尺寸提示 |

挂载点的开关放在全局配置里：

```
~/.config/tmoe-linux/rootful/mount_sd.conf
~/.config/tmoe-linux/rootful/mount_termux.conf
```

## 为什么不直接调用它的启动器

看过源码就明白了，两个硬伤：

### 1. 全局挂载，靠退出时 `umount` 清理

```bash
su -c "${TMOE_MOUNT} -o bind ${SD_DIR_0} ${ROOTFS_DIR}/media/sd &>/dev/null"
```

没有私有命名空间。TMOE 自己在提示文件里都写了：

> 移除容器前若发现部分已挂载目录无法强制卸载，请重启设备再卸载 chroot 容器

这正是 [第 04 章](04-mount-safety.md) 那场事故的同款风险。

### 2. 交互式脚本

598 行里有大量菜单 `read`，没法后台化，也没法注入我们需要的环境变量（`MESA_LOADER_DRIVER_OVERRIDE`、`DISPLAY`、`XDG_RUNTIME_DIR`）。

## 我们的做法

**只读取配置，然后在自己这边重新实现挂载**：

```bash
# scripts/termux-gui-lib.sh
tmoe_resolve        # 解析 MOUNT_SD / MOUNT_TERMUX / CHROOT_USER / UID / GID / HOME
tmoe_write_mounts   # 生成挂载脚本，在私有命名空间内 source
```

生成的挂载语句长这样，全部在 `--make-rprivate` 之后执行：

```sh
[ -d "/data/media/0/Download" ] && {
  mkdir -p "$D/media/sd"
  busybox mount --bind "/data/media/0/Download" "$D/media/sd"
}
```

好处：

- 你在 TMOE 菜单里改挂载点，本项目自动跟随，不用改代码
- 挂载只存在于会话私有命名空间，退出即销毁，**不可能泄漏**
- 可以自由注入 GPU 与显示相关的环境变量

## 用户身份

TMOE 的主用户（如 `pad`，UID 1001）现在也是桌面用户：

```bash
# 从容器 /etc/passwd 解析 UID/GID/HOME
pad:x:1001:60000::/home/pad:/bin/sh
```

然后通过 `setpriv` 在 chroot 内降权：

```bash
/usr/bin/setpriv --reuid=1001 --regid=60000 --init-groups /bin/bash -l
```

配套处理：

- `XDG_RUNTIME_DIR=/tmp/runtime-pad`，并 `chown 1001:60000`
- Xfce 配置从 `/root/.config` 复制一份到用户家目录，并强制 `use_compositing=false`
- 需要 root 桌面时：`DESKTOP_AS_ROOT=1`

> **注意**：容器内的 UID 1001 在 Android 侧会显示为 `radio`（Android 的 `aid_radio`）。功能正常，但如果你在意权限边界，可以在容器 `/etc/passwd` 里换一个空闲 UID。

## 边界总结

| 职责 | 归属 |
|---|---|
| 创建/删除容器、装发行版 | TMOE |
| 挂载点配置、默认用户 | TMOE（本项目读取） |
| Mesa/KGSL、X11、合成器 | 本项目 |
| 命名空间隔离与清理 | 本项目 |
| 桌面会话生命周期 | 本项目 |

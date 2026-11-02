# 06 · 排障手册

按症状查表。所有命令都在 Termux 中执行，涉及容器的加 `su -c`。

## 启动类

| 症状 | 检查 | 处理 |
|---|---|---|
| `X 服务启动失败` | `tail $PREFIX/tmp/termux-gui/x11.log` | 常见为 `Could not create lock file in /tmp`，说明 `TMPDIR` 不对；或 socket 残留未清理 |
| `X 服务就绪` 但画面 `Not connected` | `ls -l $PREFIX/tmp/.X11-unix/` | socket 存在但无进程 = 僵尸，删除后重启 |
| X 进程反复崩溃 `std::bad_alloc` | 应用与服务端版本 | 两者必须同版本，重新安装其中一方 |
| `容器内找不到 startxfce4` | `ls $CONTAINER/usr/bin/startxfce4` | 容器内 `apt install xfce4` |
| 启动脚本卡住不返回 | `cat $PREFIX/tmp/termux-gui/session.log` | 多为首次 `su` 授权弹窗未点，先在 Termux 执行 `su -c id` |

## 画面类

| 症状 | 原因 | 处理 |
|---|---|---|
| 整屏白 | 合成器走了 GLX | 确认 `use_compositing=false`，或改用 `COMPOSITOR=picom` |
| 整屏黑（有指针） | picom 的 glx 后端 | 删掉 picom 进程，改用 `xrender` |
| 画面冻结在某一帧 | 合成器被事后杀掉 | 只能重启会话，合成开关必须在启动前生效 |
| `renderer: llvmpipe` | Mesa 被系统更新覆盖 | 重装 KGSL 版 Mesa，`apt-mark hold` |

## 挂载类

```bash
# 检查是否有泄漏（正常应为 0）
grep -cF "$CONTAINER" /proc/mounts

# 检查会话是否还在
ps -A -o PID,ARGS | grep "chroot $CONTAINER"
```

| 症状 | 处理 |
|---|---|
| 有残留挂载 | 先 `termux-gui-stop.sh --force`；仍不清则重启设备（不要手删目录） |
| `isolation failed: shared=N` | busybox 路径不对，或内核限制；检查 `BUSYBOX` 变量 |
| `mount: bad /etc/fstab` | 用了 toybox 的 mount，换 busybox |

## 应用类

| 症状 | 原因 | 处理 |
|---|---|---|
| code 立即退出 / 窗口闪退 | 容器内无 /dev/shm，且 setuid 沙箱不可用 | 用 --no-sandbox --disable-dev-shm-usage 启动，详见 [07](07-electron-apps.md) |
| VS Code 报 launch-failed (1002) | 崩溃后配置目录损坏 | 删除/备份 ~/.config/Code 后重试 |
| sudo 报 setuid 错误 | 容器内 setuid 失效 | 用 setpriv 降权，或从 root 侧执行 |

## 系统级异常

| 症状 | 可能原因 | 处理 |
|---|---|---|
| 所有 App 启动即崩 | binderfs 节点丢失 | 重启设备；检查是否发生过挂载泄漏 |
| Termux 打不开 | 同上 | 同上 |

## 诊断命令速查

```bash
# GPU 是否走 KGSL
MESA_LOADER_DRIVER_OVERRIDE=kgsl glxinfo -B | grep -E "renderer|direct rendering"

# X 服务进程（注意看 cmdline，不是 comm）
ps -A -o PID,ARGS | grep termux-x11

# 合成器是否在跑
ps -A -o PID,ARGS | grep "picom --backend"

# 合成是否生效（应无输出表示未合成）
xwininfo -root -children | grep -i overlay

# 容器内进程
su -c "sh -c 'for l in /proc/[0-9]*/root; do readlink \$l; done | grep -c $CONTAINER'"
```

## 日志位置

| 文件 | 内容 |
|---|---|
| `$PREFIX/tmp/termux-gui/session.log` | 容器启动与桌面输出 |
| `$PREFIX/tmp/termux-gui/x11.log` | X 服务端日志 |
| `$PREFIX/tmp/termux-gui/picom.log` | 合成器日志 |

## 停止脚本与共享 UID

Termux 和 Termux:X11 通常共用同一个 Android UID：

```
package:com.termux.x11 uid:10234
package:com.termux     uid:10234
```

这种情况下 `am force-stop com.termux.x11` 会**按 UID 杀进程**，把 Termux 本体一起带走。
正确做法是只结束 X11 应用自己的进程：

```bash
p=$(pidof com.termux.x11 || ps -A -o PID,NAME | grep -w com.termux.x11 | awk '{print $1}')
[ -n "$p" ] && kill "$p"
```

另外，脚本里所有进程扫描都应避免「每进程 fork 一次」——700 个进程逐个 `readlink`
或 `tr | grep`，会让一次停止从 3 秒涨到 40 秒以上。推荐一次性 `ls -l /proc/*/root`
再 `grep`/`sed` 解析，或 `ps -A -o PID,ARGS` 单次输出后过滤。
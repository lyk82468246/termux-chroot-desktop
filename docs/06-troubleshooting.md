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
## sudo 报 "must be owned by uid 0 and have the setuid bit set"

这**不是** sudo 配置错误。容器里的 `/usr/bin/sudo` 通常是 `-rwsr-xr-x root:root`，
sudoers 里也有对应的 `NOPASSWD` 规则，但依然报错，原因是：

```
/dev/block/dm-55 /data f2fs rw,...,nosuid,nodev,...
```

Android 的 `/data` 以 **`nosuid`** 挂载，而 chroot 根文件系统就在 `/data` 上，
所以内核会**忽略所有 setuid 位**。sudo 启动时发现自己不是 euid 0，于是报那句错。
同一个原因也让 `chrome-sandbox` 失效（Electron 需要 `--no-sandbox`）。

### 为什么 TMOE 启动时看起来正常

TMOE 的启动器是**以 root 进入 chroot，再用 `sudo -Eu <user>` 降权**：

```bash
/usr/bin/sudo -Eu pad /bin/bash -l
```

这是 root → 普通用户，不需要 setuid 提升，所以不受 nosuid 影响。
而你在 pad shell 里执行 `sudo apt ...` 是反方向（普通用户 → root），才会失败。

### 解决：把 sudo 放到 tmpfs 上

tmpfs 允许 suid。在会话命名空间里准备一份带 setuid 的 sudo 副本：

```bash
mkdir -p "$D/run/sudobin"
mount -t tmpfs -o mode=0755,uid=0,gid=0 tmpfs "$D/run/sudobin"
cp "$D/usr/lib/cargo/bin/sudo" "$D/run/sudobin/sudo"
chown 0:0 "$D/run/sudobin/sudo"
chmod 4755 "$D/run/sudobin/sudo"
chroot "$D" /bin/ln -sf /run/sudobin/sudo /usr/local/bin/sudo
```

`/usr/local/bin` 在 PATH 中优先于 `/usr/bin`，所以用户直接敲 `sudo` 就会用上这份副本。

本项目的 `termux-gui-start.sh` 和 `termux-gui-attach.sh` 都会自动做这件事
（`sudo` 是 sudo-rs 时路径为 `/usr/lib/cargo/bin/sudo`）。验证：

```bash
sudo -n id      # 期望 uid=0(root)
```

### 不推荐的做法

- `mount -o remount,suid /data`：会影响整个 Android，破坏系统安全模型。
- 直接 `chmod u+s`：在 nosuid 挂载上无效，改了也白改。
## GUI 终端中文乱码

不是字体问题（中文字体通常都在），是 **locale 没传进会话**。

启动器用 `env -i` 拉起桌面，如果没显式给 `LANG`，进程会落到 `POSIX`：

```
LANG=
LC_CTYPE="POSIX"
```

GTK/VTE 在非 UTF-8 locale 下会把多字节字符当单字节处理，于是中文变成乱码。

### 检查

```bash
locale | head -3            # LC_CTYPE 是 POSIX 就是这个问题
locale -a | grep -i zh_CN   # 容器里是否生成了中文 locale
```

如果 `locale -a` 里没有中文，先在容器内生成：

```bash
locale-gen zh_CN.UTF-8 && update-locale LANG=zh_CN.UTF-8
```

### 处理

本项目在 start/attach 里显式传 locale，默认 `en_US.UTF-8`（UTF-8 + 英文界面，
不会再乱码）：

```bash
LANG="$ULOCALE" LC_ALL="$ULOCALE"
```

想要中文界面可以覆盖：

```bash
LOCALE=zh_CN.UTF-8 bash ~/bin/termux-gui-start.sh
```

> 注意：TMOE 的 `~/.config/tmoe-linux/locale.txt` 里通常写着 `zh_CN.UTF-8`，
> 但 TMOE 自己的会话才会读取它；本项目默认不跟随，避免把界面切成中文。

### 为什么"我没改语言也会乱码"

乱码和界面语言是两件事：
- **界面语言**由 `LANG` 的 messages 部分决定；
- **字符编码**由 `LC_CTYPE` 决定。

之前两者都是 POSIX，所以界面是英文、中文却是乱码。现在 `LC_CTYPE` 是 UTF-8，
界面仍是英文，中文正常显示。
## X 进程还在，但 socket 没了（会话"假活")

症状：

- `start` 说"桌面已在运行"，但任何图形程序都连不上 X
- `$PREFIX/tmp/.X11-unix/` 目录消失或为空
- `ps` 里 `termux-x11` 进程却活着

根因是**退出竞态**：X 关闭时会 `unlink` 自己的 socket 再 `rmdir` 目录。
如果旧 X 还没退干净就启动新 X，旧实例的清理动作会把**新实例**刚建好的
socket 删掉。新 X 继续活着，但路径已经不存在，客户端全部连不上。

另一个放大问题的因素：`x11_pids` 之前用 `ps -A -o PID,ARGS | grep ...` 判断，
在不同 PATH 下（Termux 的 procps vs Android toybox）行为不一致，可能漏掉进程，
于是脚本误判"X 已死"而反复启动新实例，冲突信息是
`Cannot establish any listening sockets - Make sure an X server isn't already running`。

现在的处理：

1. **检测走 /proc**，不依赖 `ps` 实现：
   ```bash
   for f in $(grep -la "termux-x11 com" /proc/[0-9]*/cmdline 2>/dev/null); do
     p=${f#/proc/}; p=${p%/cmdline}
     [ "$(cat /proc/$p/comm 2>/dev/null)" = "main" ] && echo "$p"
   done
   ```
   （X 的 `comm` 是 `main`，因为它是 app_process）
2. **先等旧 X 真正退出**再启动新实例（`kill_x11_and_wait`），最多等 5 秒，超时用 `kill -9`。
3. 启动前 `mkdir -p $PREFIX/tmp/.X11-unix && chmod 1777`，避免目录被 rmdir 后无法重建。
4. `start` 分三种状态处理：socket+进程正常 / 只有进程（自动重启 X）/ 只有 socket（清残留后启动）。
5. 如果**桌面进程在但 socket 丢失**，`start` 明确报错并让用户先 `stop`，不再假装成功：
   ```
   [!] 桌面进程在，但 X socket 丢失（会话已不可用）
   [!] 请执行: bash termux-gui-stop.sh 然后重新 start
   ```
6. `stop` 会等 X 退出后再删 socket，并重建 1777 目录。

验证方式（连续跑不会退化）：

```bash
for i in 1 2 3; do
  bash ~/bin/termux-gui-stop.sh
  bash ~/bin/termux-gui-start.sh
  ls ~/../usr/tmp/.X11-unix/      # 应该有 X0
done
```
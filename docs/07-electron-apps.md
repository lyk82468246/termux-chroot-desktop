# 07 · Electron 应用（VS Code）起不来的原因

症状：终端里敲 `code` 立即返回，或者窗口闪一下就消失；有时能看到窗口但提示
`The window terminated unexpectedly (reason: 'launch-failed', code: '1002')`。

这不是 VS Code 的问题，是 **chroot 环境缺两样东西**。

## 原因一：没有 `/dev/shm`

Chromium/Electron 需要 POSIX 共享内存。我们的 `/dev` 是从 Android 整体 bind 进去的，而 Android 的 `/dev` 里没有 `shm`：

```
FATAL:base/memory/platform_shared_memory_region_posix.cc:218
Unable to access(W_OK|X_OK) /dev/shm: No such file or directory (2)
This is frequently caused by incorrect permissions on /dev/shm.
```

进程直接 abort（`rc=133`，SIGTRAP）。

## 原因二：setuid sandbox 不可用

`/usr/share/code/chrome-sandbox` 虽然带 `4755` 位，但在这种情况下 setuid 不生效
（Android 的 `/dev`、部分文件系统挂 nosuid），Chromium 会拒绝启动。

## 解决：两个启动参数

```bash
/usr/share/code/code --no-sandbox --disable-dev-shm-usage
```

- `--no-sandbox`：跳过 setuid 沙箱
- `--disable-dev-shm-usage`：让 Chromium 用 `/tmp` 代替 `/dev/shm`

**不需要 `--disable-gpu`**。GPU（KGSL/freedreno）可以正常参与渲染，加了这个参数反而浪费。

## 固化：包装脚本

`PATH` 里 `/usr/local/bin` 优先于 `/usr/bin`，所以放一个同名包装即可：

```bash
cat > /usr/local/bin/code <<'EOF'
#!/bin/sh
exec /usr/share/code/code --no-sandbox --disable-dev-shm-usage "$@"
EOF
chmod 755 /usr/local/bin/code
```

验证：

```bash
which code          # /usr/local/bin/code
ps -A -o ARGS | grep "code --no-sandbox"
```

## 从菜单启动：补一个 desktop entry

如果用 tarball 安装，可能没有 `.desktop` 文件。给桌面用户建一个：

```ini
[Desktop Entry]
Type=Application
Name=Visual Studio Code
Exec=/usr/share/code/code --no-sandbox --disable-dev-shm-usage --unity-launch %F
Icon=vscode
Terminal=false
Categories=TextEditor;Development;IDE;
StartupNotify=true
StartupWMClass=Code
```

放到 `~/.local/share/applications/code.desktop` 并确保属主是桌面用户。

## 如果出现 `launch-failed (1002)`

这通常**不是**参数问题，而是之前的崩溃把用户配置写坏了。清理后重试：

```bash
pkill -f /usr/share/code/code
mv ~/.config/Code ~/.config/Code.bak
rm -rf ~/.vscode-shared
code
```

实测：在 `/dev/shm` 缺失的状态下崩溃过一次之后，默认配置目录就会稳定复现 1002；换一个干净目录（或删掉旧目录）立刻恢复正常，GPU 依然开启。

## 顺带发现：容器里的 sudo 不可用

```
sudo: sudo must be owned by uid 0 and have the setuid bit set
```

同样是 setuid 失效。所以本项目用 `setpriv --reuid/--regid` 降权，而不是 `sudo`——这也是为什么启动脚本不依赖容器内的 sudo。

## 其他 Electron 应用

同样的两个参数通常都适用（`--no-sandbox --disable-dev-shm-usage`）。如果某个应用不认命令行参数，可以考虑给 chroot 提供真正的 `/dev/shm`：不要整体 bind `/dev`，而是挂 tmpfs 到 `/dev` 后按需 `mknod`/bind 设备节点，再 `mkdir /dev/shm && mount -t tmpfs tmpfs /dev/shm && chmod 1777`。本项目暂未采用，因为整体 bind `/dev` 对 GPU 节点更省事。

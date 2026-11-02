# 08 · 安装非 snap 版 Firefox

Ubuntu 26.04 的 `firefox` 包是一个**过渡包**，安装后只会提示你去 `snap install firefox`。在 chroot 里 snap 基本不可用（没有 systemd、没有 snapd），所以必须用 Mozilla 官方的 deb 源。

## 为什么不用 snap

```
$ /usr/bin/firefox
Command '/usr/bin/firefox' requires the firefox snap to be installed.
Please install it with: snap install firefox
```

容器里没有 systemd，`snapd` 起不来；即使装上也无法正常启动。

## 安装步骤

```bash
# 1. 依赖
apt-get install -y --no-install-recommends curl ca-certificates gnupg

# 2. Mozilla 签名密钥
install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg \
  -o /etc/apt/keyrings/packages.mozilla.org.asc

# 3. APT 源
echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
  > /etc/apt/sources.list.d/mozilla.list

# 4. 固定优先级，避免被 Ubuntu 的过渡包覆盖
printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' \
  > /etc/apt/preferences.d/mozilla

# 5. 更新并安装
apt-get update
apt-get install -y --allow-downgrades firefox
```

## 关键点：`--allow-downgrades`

Ubuntu 预装的过渡包版本号是 `1:1snap1-0ubuntu9.1`，Mozilla 的是 `159.0~build1`。
按版本比较这是"降级"，不加参数会直接失败：

```
E: Packages were downgraded and -y was used without --allow-downgrades.
```

加 `--allow-downgrades` 后会用真正的 deb 覆盖过渡包：

```
Unpacking firefox (159.0~build1) over (1:1snap1-0ubuntu9.1) ...
Setting up firefox (159.0~build1) ...
```

安装后 `/usr/bin/firefox` 指向 `/usr/lib/firefox/firefox`，不再是 snap 包装脚本。

## 验证

```bash
dpkg -l firefox | tail -1     # ii  firefox  159.0~build1  arm64
/usr/lib/firefox/firefox --version
```

在桌面里启动：

```bash
firefox --new-instance &
```

实测可正常打开新标签页，中文书签、GPU 渲染均正常。日志里的
`WARNING: Glycin running without sandbox` 与 `Couldn't open video device /dev/video*`
是无害的（容器没有摄像头节点）。

## 已知注意

1. **DNS 可能间歇失败**。如果安装时报 `Could not resolve 'packages.mozilla.org'`，
   检查容器 `/etc/resolv.conf`，建议写多个解析器：
   ```
   nameserver 223.5.5.5
   nameserver 119.29.29.29
   nameserver 8.8.8.8
   ```
2. **以后升级**：`apt update && apt install firefox` 会继续走 Mozilla 源；
   不要安装 Ubuntu 的 `firefox` snap 过渡包，否则会把 deb 版覆盖回去。
3. 如果某天 Mozilla 源不可用，还可以用官方 tarball：从
   `https://www.mozilla.org/firefox/all/` 下载 `linux-aarch64` 版，解压到
   `/opt/firefox` 并软链到 `/usr/local/bin/firefox`。

## GPU 加速：默认是关的

Mozilla 打包的 Firefox 默认会做一次 "glxtest"（探测 GL/EGL 是否可用）。在
Termux:X11 + Mesa/KGSL 这套组合下，这个探测经常失败，Firefox 于是**静默回落到
软件 WebRender**——界面能用，但完全不碰 GPU。

### 怎么判断它有没有用 GPU

看进程有没有打开 GPU 设备节点，比看界面可靠得多：

```bash
for d in /proc/[0-9]*; do
  c=$(cat "$d/comm" 2>/dev/null) || continue
  case "$c" in firefox*|"Web Content"*|"Isolated Web"*) ;; *) continue ;; esac
  p=${d#/proc/}
  hit=$(ls -l "$d/fd" 2>/dev/null | grep -E "kgsl|/dev/dri" | sed 's/.*-> //')
  echo "pid=$p comm=$c dev=[$hit]"
done
```

- **空** → 软件渲染
- **`/dev/kgsl-3d0`** → WebRender 走 GPU（Mesa 的 KGSL 后端）

### 打开 GPU

在 profile 目录写 `user.js`（每次启动都会合并进 prefs，比改 `prefs.js` 稳妥）：

```bash
PROF=$(ls -d ~/.config/mozilla/firefox/*.default* | head -1)
cat > "$PROF/user.js" <<'EOF'
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.software", false);
user_pref("layers.acceleration.force-enabled", true);
user_pref("webgl.force-enabled", true);
user_pref("gfx.canvas.accelerated", true);
EOF
```

重启 Firefox 后复查上面的 `fd` 检查，应该能看到 `/dev/kgsl-3d0`。

> 注意：Ubuntu 上的 profile 可能不在 `~/.mozilla` 而在 `~/.config/mozilla`
> （取决于 `XDG_CONFIG_HOME`）。用 `find ~ -name prefs.js` 定位最快。

### 想关回去

删掉 `user.js` 里那几行（或整个文件）重启即可。软件渲染更省电，GPU 渲染更顺滑，
在 Adreno 610 这种低端 GPU 上差别不算大，可以按需选择。
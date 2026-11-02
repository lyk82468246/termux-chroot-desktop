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

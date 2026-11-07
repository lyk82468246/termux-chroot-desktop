# 09 · 容器内默认开启 sshd

启动脚本会在会话里自动拉起 `openssh-server`，监听 **2222** 端口。

## 为什么是 2222

chroot 与 Android 共享网络栈。22 端口容易和别的服务或后续安装的东西冲突，
2222 更安全；需要改的话：

```bash
SSHD_PORT=22 bash ~/bin/termux-gui-start.sh
```

不想开：

```bash
SSHD=0 bash ~/bin/termux-gui-start.sh
```

## 配置

装在容器里的 `openssh-server` 加上一份 drop-in：

```ini
# /etc/ssh/sshd_config.d/10-termux-gui.conf
Port 2222
ListenAddress 0.0.0.0
PermitRootLogin no
PasswordAuthentication yes
PubkeyAuthentication yes
AllowUsers pad
X11Forwarding no
AllowTcpForwarding yes
UseDNS no
GSSAPIAuthentication no
UsePAM no
PidFile /run/sshd.pid
```

几个非默认项的原因：

| 项 | 原因 |
|---|---|
| `UsePAM no` | 容器里没有 systemd，`pam_systemd` 可能卡住会话建立 |
| `UseDNS no` | 避免登录时反向解析卡顿 |
| `GSSAPIAuthentication no` | 容器没有 Kerberos，关掉省一次失败尝试 |

`PermitRootLogin no` 是刻意的：容器里 `pad` 用 `sudo` 提权（见
[06](06-troubleshooting.md) 的 tmpfs sudo 方案），不需要 root 直接登录。

## 启动方式

容器没有 systemd，所以 sshd 由启动脚本在会话命名空间里直接拉起：

```bash
chroot "$D" /usr/sbin/sshd -D -e -p "$SSHD_PORT" >>"$PREFIX/tmp/termux-gui/sshd.log" 2>&1 &
```

用 `-D -e` 是因为容器里没有 syslog——否则日志会丢失，出问题完全没线索。
日志在 `$PREFIX/tmp/termux-gui/sshd.log`。

## 认证

### 公钥（推荐）

把公钥追加到容器的 `/home/pad/.ssh/authorized_keys`：

```bash
mkdir -p "$D/home/pad/.ssh"
cat your_key.pub >> "$D/home/pad/.ssh/authorized_keys"
chown -R 1001:60000 "$D/home/pad/.ssh"
chmod 700 "$D/home/pad/.ssh"
chmod 600 "$D/home/pad/.ssh/authorized_keys"
```

### 密码

`pad` 已有密码哈希，直接改密码即可：

```bash
sudo passwd pad
```

## 怎么连

### 同网段且没有 AP 隔离

```bash
ssh -p 2222 pad@<设备IP>
```

### Wi-Fi 开了 AP 隔离（常见）

设备之间互相不可见，但可以用 adb 走 USB 转发：

```bash
adb forward tcp:2222 tcp:2222
ssh -p 2222 pad@127.0.0.1
```

### 从容器内部验证

```bash
ssh -p 2222 pad@127.0.0.1 'id'
```

## 坑一：生成密钥时 `-N '""'` 会变成口令

在 PowerShell 里这样写：

```powershell
ssh-keygen -t ed25519 -N '""' -f key
```

`""` 会被当成**两个引号字符的口令**，密钥就成了加密的。表现很有迷惑性：

- 服务端日志显示 `Accepted key ...`（它只需要公钥，不需要口令）
- 客户端却失败，`ssh -vvv` 里是

  ```
  debug3: sign_and_send_pubkey: signing using ssh-ed25519
  debug2: we did not send a packet, disable method
  ```

  `we did not send a packet` 就是**签名失败**（需要口令但拿不到）。

正确做法是用 Git Bash 生成（单引号是真空串）：

```bash
ssh-keygen -t ed25519 -N '' -f ~/.ssh/key
ssh-keygen -y -P '' -f ~/.ssh/key   # 能直接输出公钥 = 没有口令
```

## 坑二：设备 IP 会变

`192.168.196.251` 是设备的 **ZeroTier** 地址（接口 `ztukuvm32f`），
Wi-Fi 地址是另一套（例如 `10.223.69.61`）。换网络后旧地址就超时了：

```bash
adb shell ip -4 addr show wlan0 | grep inet
```

## 已知问题：Windows 自带 ssh 客户端握手失败

Windows 10/11 自带的 OpenSSH（9.5p2）在这里会卡在签名阶段：

```
debug3: sign_and_send_pubkey: using publickey-hostbound-v00@openssh.com
debug3: sign_and_send_pubkey: signing using ssh-ed25519
debug2: we did not send a packet, disable method
```

服务端日志对应的是 key 已经 `Accepted`、回了 PK_OK，然后客户端自己断开。

**更正**：这条最初被我归因成"Windows 客户端 bug"，实际根因是**密钥带口令**
（见上面"坑一"）。`we did not send a packet` 是客户端签名失败——它要口令，
但 `BatchMode` 下拿不到，于是直接放弃。

换成真空串口令的密钥后，Windows 自带 ssh 和 Git Bash 的 ssh 都能正常登录：

```bash
ssh -p 2222 pad@127.0.0.1        # 配合 adb forward
```

排查这类问题的通用判据：

| 现象 | 含义 |
|---|---|
| `Accepted key` + 客户端 `we did not send a packet` | 客户端签名失败（多半是密钥口令） |
| `Permission denied` 且服务端没有 `Accepted key` | 公钥没匹配上（authorized_keys / 权限） |
| `Accepted publickey` 后卡住 | 会话阶段问题（PAM、DNS、pty） |

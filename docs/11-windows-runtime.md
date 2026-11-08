# 11 · Windows Runtime（M1：ARM64 基础运行时）

M1 的目标只有一个：**把 Spike 验证过的 ARM64 Wine 正式装进容器，并融入现有桌面**。
统一 `win-run` 入口、AMD64/IA-32 正式支持、DXVK、应用菜单都不在 M1 范围内。

## 前置要求

| 项 | 要求 |
|---|---|
| 架构 | arm64 |
| 发行版 | Ubuntu 26.04（codename `resolute`） |
| 磁盘 | 至少 8 GB 可用（默认检查值，可用 `MIN_FREE_GB=12` 覆盖） |
| 桌面 | 已用 `termux-gui-start.sh` 启动过一次 |
| 用户 | TMOE 主用户（默认 `pad`），Prefix 绝不用 root 创建 |

## 安装

```bash
# 只体检，不改系统
bash ~/bin/termux-win-install.sh --check

# 正式安装（可重复执行，已装的不会重装）
bash ~/bin/termux-win-install.sh
```

安装过程：

1. 校验架构 / codename / 磁盘空间；
2. 下载并校验两个上游 tar（SHA-256 硬编码在脚本里）；
3. 解包出 4 个 deb（3 个小包 + wine 主包 ~287 MB）；
4. 在私有 mount namespace 里挂 `proc`/`sysfs`/`dev`/`dev/shm`，然后 `apt-get install` 本地 deb；
5. 写版本记录 `/etc/termux-win-runtime.version`；
6. 以桌面用户身份初始化 Prefix（首次约 2.5 GB）。

## 安装后的布局

```
/home/pad/.local/share/termux-chroot-desktop/wine/
├── prefixes/default/     # 单一 WoW64 Prefix
├── logs/
└── config/
```

## 验证

```bash
# 容器内
wine --version                       # wine-11.16 (Hangover)

export WINEPREFIX="$HOME/.local/share/termux-chroot-desktop/wine/prefixes/default"
wine cmd /c "echo ok"

# GUI（现有 XFCE 里开窗）
wine /usr/lib/wine/aarch64-windows/notepad.exe
```

M1 实测结果（真机）：

| 验收项 | 结果 |
|---|---|
| 4 个 deb 安装，APT 状态正常 | PASS |
| SHA-256 / 版本记录可复现 | PASS |
| Prefix 创建、关闭、重新打开 | PASS（重启会话后 `wine cmd` 仍可用） |
| ARM64 Notepad 在 XFCE 显示 | PASS |
| Wine 内 OpenGL = FD610 / Mesa 27 | PASS |
| Z: 盘读写（`Z:\home\pad\...`） | PASS |
| 真实音频播放（winmm `PlaySound` + `SND_SYNC`） | PASS（`PLAY_OK`，仍需人耳确认） |
| `/dev/shm` 在 start / attach 两条路径可用 | PASS |
| stop → start 后 wineserver 无残留、Prefix 正常 | PASS |

## `/dev/shm` 是怎么处理的

容器 `/dev` 是 Android devtmpfs 的 bind，**在会话外创建 `dev/shm` 会被覆盖**。
因此顺序必须是：

```
unshare -m
  → mount --make-rprivate /
  → mount proc / sysfs
  → mount --bind /dev
  → mkdir $D/dev/shm            # 此时落在 devtmpfs
  → mount -t tmpfs -o size=256M,mode=1777 tmpfs $D/dev/shm
  → chroot
```

`start` 与 `attach` 各自有独立的 mount namespace（实测 `mnt:[4026533297]` vs `mnt:[4026534078]`），
所以两边都要执行，不能指望复用。共用逻辑在 `scripts/termux-gui-lib.sh` 的
`write_shm_helper()` 生成的 `ensure-dev-shm.sh` 里。

容量可通过 `WIN_SHM_SIZE=512M` 调整。

## 已知限制（M1 不做）

1. **没有统一 `win-run`**：现在要手动设置 `WINEPREFIX` 再调用 `wine`。
2. **AMD64 / IA-32 无正式入口**：底层可用（Spike 已验证 FEX / Box64），但没有封装。
3. **Wine Mono 弹窗**：未安装 wine-mono 时首次运行会弹安装器。
   安装脚本只在**初始化 Prefix 时**临时用 `WINEDLLOVERRIDES=mscoree,mshtml=` 避免卡住，
   不改变 Prefix 的长期能力；需要 .NET 的应用请后续安装 wine-mono。
4. **ARM32 PE 不支持**：日志里可能出现 `sysarm32\rundll32.exe` 的 `c0000135`，属预期。
5. **音频只验证到 `PlaySound` 返回成功**，人耳确认请在设备上做一次。

## 回滚

```bash
# 卸载运行时（Prefix 会保留）
apt remove -y hangover-wine hangover-libarm64ecfex hangover-libwow64fex hangover-wowbox64

# 只有在确认不需要用户数据时才删 Prefix
rm -rf ~/.local/share/termux-chroot-desktop/wine/prefixes/default
```

> 软件包（2.4 GB，在 `/usr`）和 Prefix（2.5 GB，在 `$HOME`）是**两回事**：
> 卸载软件包不会删 Prefix，删 Prefix 也不影响软件包。

## M1.1 安装器可靠性

M1.1 修掉了三类"静默成功"隐患：

1. **退出码传播**：`apt-get` / `wineboot` 的返回值现在会 `exit` 出去，
   外层用 `rc=$?` 判定，不再被后面的 `echo` 覆盖。
2. **安装后校验**：`dpkg --audit` + `apt-get check`，并逐个确认四个包都是
   `install ok installed`。
3. **Prefix 校验**：检查 `drive_c`、`system.reg`，并以桌面用户执行
   `wine cmd /c exit 0`，同时校验 Prefix 属主等于桌面用户 UID。

安装器的 root helper 全部运行在 `unshare -m` 里，并自带隔离自检
（`shared:` 计数必须为 0），避免把 proc/sysfs/dev 挂载泄漏到全局。

故障注入结果（真机）：

| 场景 | 期望 | 结果 |
|---|---|---|
| `--check` | 通过且不改系统 | PASS |
| 正常幂等安装 | 跳过 prefix 初始化 | PASS |
| apt-get 返回失败 | 安装器失败 | PASS |
| wineboot 返回失败 | 安装器失败 | PASS |
| Prefix 属主错误 | 明确报错 | PASS |
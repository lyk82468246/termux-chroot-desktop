# 14 · 交接说明（给下一个 Agent）

这份文档的目标：**让接手的 Agent 在不读完整聊天记录的情况下，30 分钟内知道
项目做到哪、环境怎么连、哪些坑已经踩过、下一步该做什么。**

先读这一页；需要细节时再跳到对应章节。

---

## 1. 项目一句话

在 Lenovo TB331FC（Android 15 + KernelSU）上，用 Termux + TMOE chroot 跑
Ubuntu 26.04 XFCE 桌面，并把 Wine（Hangover 11.16）做成支持
**ARM64 / AMD64 / I386** 三种 Windows PE 的运行环境。

当前状态：桌面、三架构 Wine、D3D9/10/11 的 WineD3D 硬件渲染都已验证；
**DXVK 因 Adreno 610 缺 `multiViewport` 不可用**（已查清，不是配置问题）；
一个真实应用 Office Tool Plus 的 GUI 启动崩溃问题**尚未解决**。

---

## 2. 设备与环境

| 项 | 值 |
|---|---|
| 设备 | Lenovo TB331FC，SM6225 / Adreno 610，Android 15，KernelSU root |
| adb | `C:\Program Files (x86)\搞机助手\adb.exe`，序列号 `HA1X2NJZ` |
| Termux home | `/data/data/com.termux/files/home` |
| 容器根 | `$HOME/.local/share/tmoe-linux/containers/chroot/ubuntu-resolute_arm64` |
| 容器用户 | `pad`（TMOE 配置），`HOME=/home/pad` |
| Wine Prefix | 容器内 `~/.local/share/termux-chroot-desktop/wine/prefixes/default` |
| 桌面 | Termux:X11 `:0` + XFCE，`DISPLAY=:0` |

**设备可能不在线。** 接手先检查：

```powershell
& "C:\Program Files (x86)\搞机助手\adb.exe" devices
```

为空时：USB 连接并开启 USB 调试，或 `adb connect <平板IP>:5555`（需先开无线调试）。

### 权限与调用约定

- 设备上的 root 操作统一用 `su -c "..."`；以 Termux 应用身份运行时用
  `su 10234 -c "..."`，并且**必须显式传 `HOME=`**（`su 10234` 会把 HOME 设成 `/`）：
  ```powershell
  adb shell su 10234 -c "export HOME=/data/data/com.termux/files/home; bash ..."
  ```
- 从 adb 里跑复杂命令时，**优先把命令写成脚本 push 到 `/data/local/tmp/` 再执行**，
  嵌套引号在 `su -c` + PowerShell 下极易被吃掉（本项目在这上面浪费过很多时间）。
- 容器内脚本以 `pad` 运行时，需要把文件 `chown 1001:60000`（pad 的 uid/gid）。

---

## 3. 仓库结构

```
scripts/                     Termux 侧桌面生命周期
  termux-gui-lib.sh          解析 TMOE 配置（只读）
  termux-gui-start.sh        启动 X / XFCE / sshd / pulse / shm
  termux-gui-stop.sh         停止并清理
  termux-gui-attach.sh       进容器（私有 mount namespace）
  windows/
    win-run                  容器内统一 PE 启动入口（当前主力）
    termux-win-run.sh        ⚠ 已停止维护，保留但不要用
    termux-win-install.sh    Hangover 安装器（哈希锁定）
    win-gpu-diagnose         只读图形栈诊断

tests/windows/               Windows PE 测试程序（mingw 编译）
  hello.c / args_test.c / file_test.c / gui_test.c / exit_test.c
  ia32/                      32 位版本（hello/gui32/probe/exit）
  graphics/                  D3D9 / D3D10 / D3D11 / gl_probe
  dxvk/                      M4.0 D3D11 测试 + Vulkan multiViewport 测试
  coexist.sh                 三架构共存回归

docs/                        01–13 为各阶段文档，14 为本文件
  spikes/                    M1–M4 的实验报告（含失败与证伪过程）
```

---

## 4. 里程碑状态

| 阶段 | 内容 | 状态 |
|---|---|---|
| M0 | 桌面生命周期、挂载隔离 | 完成 |
| M1 / M1.1 | Hangover 11.16 ARM64 Wine | 完成 |
| M2 / M2.1 | AMD64 + FEX，统一 `win-run` | 完成 |
| M3.0 | IA-32 Box64 vs FEX 双后端 | 完成 |
| M3.1 | IA-32 正式接入（Box64 默认，FEX 可覆盖） | 完成 |
| M3.2 | 三架构共存（同 Prefix / 同 wineserver） | 完成 |
| M4.0 | DXVK + Turnip Spike | **DXVK 阻塞**（缺 multiViewport） |
| M4.0.1/2 | multiViewport 根因调查 | 完成：驱动/硬件不实现，强制开启会画错 |
| M4.1 | WineD3D 正式支持（D3D9/10/11 × x64/x86） | 完成 |
| M4.2+ | 性能/稳定性 | 未开始 |
| M3.1.1 | Wine 控件中文方框 | 未修（独立遗留） |

最近的提交（`git log --oneline`）：

```
b58e6d2 docs(win-run): note whitespace trimming
178c768 fix(win-run): trim leading/trailing whitespace around PROG and DIR
101cedd fix(win-run): normalize --dir and PROG so relative paths with spaces resolve correctly
eb82ad7 fix(win-run): resolve relative EXE against --dir; deprecate termux-win-run.sh in docs
a51e7f3 feat(m4.1): WineD3D D3D9/10/11 verified on AMD64+IA-32; win-gpu-diagnose
```

---

## 5. 运行时架构

| PE machine | 执行路径 |
|---|---|
| `0xAA64` ARM64 | 原生 Hangover（无模拟器） |
| `0x8664` AMD64 | Hangover 自动加载 FEX（`libarm64ecfex.dll`） |
| `0x014C` I386 | 默认 WowBox64（`wowbox64.dll`）；`HODLL=libwow64fex.dll` 可切 FEX |

`win-run` 语义（重要）：

```bash
win-run app.exe [args...]
win-run --debug app.exe          # 打印 arch / Prefix / 后端与证据行
win-run --dir DIR app.exe        # DIR 规范成绝对路径；相对 EXE 按 DIR 解析
```

- 引号内**首尾空白会被去掉**；
- `--dir` 与 EXE 都会被 `realpath` 规范化（去掉 `./`、`../`）；
- 不传 `--dir` 时，工作目录 = 调用者的 pwd；
- EXE 路径必须是**容器内可见的路径**；
- `termux-win-run.sh` 已停止维护（文档已标注），不要在新流程里使用。

---

## 6. 常用命令

### 桌面生命周期（Termux 侧）

```bash
bash ~/bin/termux-gui-start.sh
bash ~/bin/termux-gui-attach.sh
bash ~/bin/termux-gui-stop.sh
```

### 从 adb 跑容器命令

```powershell
$P = "C:\Program Files (x86)\搞机助手\adb.exe"
& $P -s HA1X2NJZ push script.sh /data/local/tmp/script.sh
& $P -s HA1X2NJZ shell 'su -c "cp /data/local/tmp/script.sh <CONTAINER>/tmp/; chown 1001:60000 <CONTAINER>/tmp/script.sh; sh /data/local/tmp/run-attach.sh bash /tmp/script.sh"'
```

> `/data/local/tmp/run-attach.sh`、`run-start.sh`、`run-stop.sh`、`final-check.sh`
> 是会话期建立的辅助脚本，**重启后可能丢失**。丢失时直接用
> `~/bin/termux-gui-attach.sh` / `termux-gui-start.sh` / `stop.sh` 代替。

### 跑 Windows 程序

```bash
# 容器内
win-run /tmp/win-tests/ia32/hello.exe 5
win-run --debug /tmp/win-tests/graphics/d3d11_x64.exe --frames 60
win-run --dir "/home/pad/Office Tool" "Office Tool Plus.exe"
```

### 图形诊断（只读）

```bash
win-gpu-diagnose
```

---

## 7. 测试与验证方法

### 编译测试程序

```bash
# 容器内
bash /tmp/win-tests/build.sh            # 64 位：args/exit/gui/d3d11/gl_probe 等
bash /tmp/win-tests/ia32/build.sh       # 32 位
bash /tmp/win-tests/graphics/build.sh   # D3D9/10/11 x64+x86 + gl_probe
```

> `/tmp/win-tests` 属于容器 rootfs，**重装/清理后需要从 `tests/` 重新复制并编译**。
> 仓库只保存源码与 build.sh，不保存二进制。

### 判据（不要只看退出码）

- 后端是否真的生效：日志里必须有
  - `starting FEX (Hangover 11.16) based libarm64ecfex.dll`（AMD64）
  - `[BOX64] WowBox64 arm64 v0.4.4`（I386 默认）
  - ARM64 则两者都不应出现。
- GUI：必须看到窗口/截图，不能只凭进程存在。
- 图形：`GPU_ADAPTER` 是 Wine 的假名（固定 `NVIDIA GeForce GTX 470`），**不能作为 GPU 证据**；
  真正证据是 `GL_RENDERER=FD610`（`win-gpu-diagnose` 或 `gl_probe`）。
- 报告格式：PASS / FAIL / PARTIAL / NOT TESTED，必须如实区分。

---

## 8. 已经踩过的坑（重点，别重复）

### 8.1 GUI 测试全部失败，先怀疑 X

M3.0 时 Box64 被误判为"不能创建窗口"，实际是**桌面 X 会话已死**
（主机 `$PREFIX/tmp/.X11-unix` 消失，容器里只剩陈旧 socket）。
`CreateWindowW` 返回 NULL、`MessageBox` 返回 -1 都是这个原因。

**规则：任何 GUI 矩阵测试前，先确认 X 活着。**

```bash
xdotool getdisplaygeometry
ls -l /tmp/.X11-unix
```

### 8.2 挂载点上的 PE 不能直接执行

`/media/sd`（共享存储 bind）和 `/tmp/termux-win-run`（Termux 侧 bind）里的 EXE，
Wine 会报：

```
Application could not be started, or no application associated with the specified file.
ShellExecuteEx failed: File not found.
```

文件本身可读（`head` 能看到 `MZ`），复制到容器自身 `/tmp` 就正常。
**规则：要执行的文件必须落在容器自己的文件系统里，不要放在 bind 挂载目录。**

### 8.3 Termux 的 `$HOME` / `$PREFIX` 容器看不到

Termux home 是 `0700`，容器用户无法穿越；TMOE 虽然把 home bind 到 `/media/termux`，
仍然 Permission denied。`win-run` 会显式拒绝这类路径（退出码 2）。

### 8.4 Windows PID ≠ Linux PID

`/proc/<pid>` 是 Linux pid；Wine 里 `tasklist` 显示的是另一套 Windows PID。
跨工具传 PID 时要注意，否则会得到 `Invalid process id (87)`。

### 8.5 .NET dump 工具链在 Wine 下不可用（M4.x 调查结论）

- `dotnet-dump ps` → `System.IO.IOException: Bad device type. : '\\.\pipe\'`
  （Wine 不支持枚举命名管道设备目录）；
- `dotnet-dump collect -p` 依赖同一枚举，无法 attach；
- `createdump.exe`（`DOTNET_DbgEnableMiniDump=1`）→
  `virtual_setup_exception stack overflow 1536 bytes addr 0x6fff9e5980`，不产生 dump；
- `DOTNET_DefaultDiagnosticPortSuspend=1` → 同一栈溢出崩溃。

**这是 Wine 的限制，不是应用的问题。** 不要在这里继续投入。

### 8.6 DXVK 在本机不可用（已证伪的假设）

- Turnip 默认 `multiViewport=false`、`maxViewports=1`；
- `FD_DEV_FEATURES=has_hw_multiview=1` 能把 feature 打开，DXVK 也能初始化，
  但**原生像素测试证明非零 ViewportIndex 被忽略**（全部画进 viewport 0）；
- 因此 **不要把 `FD_DEV_FEATURES` 写进任何启动脚本**，它只会制造"看起来能跑"的假象。

证据：`docs/spikes/turnip-multiviewport-investigation.md`、`viewport-index-root-cause.md`。

### 8.7 中文方框

Wine 控件里的中文数据正确，但显示为 □。标题正常。
试过 `HKCU\Software\Wine\Fonts\Replacements` 无效。属于字体回退问题，独立遗留。

### 8.8 D3D9 默认光照会让顶点色变黑

测试程序必须 `SetRenderState(D3DRS_LIGHTING, FALSE)`，否则"有画面"但全黑，
容易误判为渲染失败。

### 8.9 `su -c` 的引号

从 adb/PowerShell 嵌套传参会被多层 shell 吃掉。**写脚本文件**，不要拼命令字符串。

---

## 9. 当前未解决的问题：Office Tool Plus GUI 崩溃

### 现象

```bash
cd "/home/pad/Office Tool"
win-run "Office Tool Plus.exe"
# rc=3
```

日志：

```
err:seh:NtRaiseException Unhandled exception code 80000003 flags 0 addr 0x6ff6df1ee0
```

### 已确认

| 项 | 结果 |
|---|---|
| PE 架构 | ARM64（原生路径） |
| OTP 版本 | 10.0.1226.42308，apphost 10.0.12，single-file bundle |
| .NET 运行时 | 10.0.14（NETCore + WindowsDesktop，coreclr arm64） |
| WebView2 | 已装 ARM64 157.0.4341.42，注册表 pv 正常 |
| Windows 版本 | 10.0.19045 |
| Console 版 | **正常**（打印 toolbox 用法） |
| GUI 版 | CoreCLR 内部 failfast |

崩溃地址落在 `coreclr.dll` 的 .text（base `0x6ff6df0000`，偏移 `0xEE0`）。

### 已排除

- WebView2 缺失 / 版本不对；
- WebView2 参数（`--no-sandbox --disable-gpu`）；
- `LIBGL_ALWAYS_SOFTWARE=1`；
- WPF 硬件加速（注册表 `DisableHWAcceleration=1`，已回滚）；
- `DOTNET_EnableWriteXorExecute=0`、`DOTNET_EnableAlternateStackCheck=0`；
- single-file 解包目录 / TEMP 改到 `Z:\tmp`；
- 目录只读（复制到 `/tmp` 后仍崩）；
- .NET dump 分析（工具链被 Wine 管道限制卡死，见 8.5）。

### 建议的下一步（按优先级）

1. **最小 WPF 探针**：用容器里的 Linux `dotnet-sdk-10.0`（已安装）交叉发布：
   ```bash
   dotnet new wpf -n wpfprobe -o /tmp/wpfprobe
   cd /tmp/wpfprobe
   dotnet publish -c Release -r win-arm64 --self-contained false \
     -p:EnableWindowsTargeting=true -o /tmp/wpfprobe-out
   ```
   然后在同一 Prefix 下运行 `/tmp/wpfprobe-out/wpfprobe.exe`。
   - 崩 → WPF/WindowsDesktop 在该 Wine 下普遍不可用；
   - 正常 → 问题在 OTP 自身，再查其依赖/版本。
2. **干净临时 Prefix**：排除当前 Prefix 被 .NET/WebView2 安装污染（约 2 GB，可删）。
3. **OTP 9.x（.NET 8 目标）**：验证是否 .NET 10 特有。
4. 若确认 WPF 不可用，考虑在文档中把它列为已知限制，暂不继续投入。

---

## 10. 协作规则（本项目一直在用）

1. **审批门**：修改正式脚本、正式 Prefix、注册表、系统包之前，先说明并等用户批准。
   未批准的修复不要做，更不要部署。
2. **不要碰**：Android 内核、全局挂载、TMOE 配置、Mesa/Turnip 替换。
3. **报告**：PASS / FAIL / PARTIAL / NOT TESTED 必须分开；禁止用环境故障冒充后端结论。
4. **提交**：小步提交，信息用 `feat(...)` / `fix(...)` / `docs(...)` / `spike(...)`；
   推送前 `git status` 应为干净。
5. **证据**：关键结论要有日志/截图/像素回读，不接受"理论上应该"。

---

## 11. 新 Agent 的前 30 分钟清单

```
[ ] adb devices 能看到设备
[ ] bash ~/bin/termux-gui-start.sh 成功；xdotool getdisplaygeometry 有输出
[ ] 容器内 win-run /tmp/win-tests/ia32/hello.exe 5 → rc=5，日志有 [BOX64]
[ ] win-run /tmp/win-tests/exit_x64.exe 5 → rc=5，日志有 starting FEX
[ ] win-gpu-diagnose → GL_RENDERER=FD610，multiViewport=false
[ ] 读 docs/13-windows-graphics.md 与 docs/spikes/ 下的 M4 报告
[ ] 读本文第 8、9 节（坑与未解决问题）
```

---

## 12. 相关文档索引

| 文档 | 内容 |
|---|---|
| `docs/01`–`05` | 前置条件、GPU、合成器、挂载安全、TMOE 集成 |
| `docs/06` | 故障排查（桌面/X/挂载） |
| `docs/09` / `10` | sshd / 音频 |
| `docs/11` | ARM64 Wine 安装 |
| `docs/12` | AMD64 + `win-run` 历史语义（含已停维护包装器） |
| `docs/13` | WineD3D D3D9/10/11 验证、`win-gpu-diagnose` |
| `docs/spikes/windows-runtime-spike.md` | M1 安装与 Wine 初始化 |
| `docs/spikes/ia32-runtime-spike.md` | M3.0 双后端对比 |
| `docs/spikes/multi-arch-coexistence.md` | M3.2 三架构共存 |
| `docs/spikes/dxvk-turnip-spike.md` | M4.0 DXVK 阻塞 |
| `docs/spikes/turnip-multiviewport-investigation.md` | M4.0.1 FD_DEV_FEATURES 实验 |
| `docs/spikes/viewport-index-root-cause.md` | M4.0.2 像素级根因 |

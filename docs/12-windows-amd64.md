# 12 · AMD64 Windows 运行时与统一入口 `win-run`（M2）

M2 只做两件事：给 Windows 程序一个统一入口，并正式支持 AMD64（经 Hangover 的 FEX）。
IA-32 仍属 M3，DXVK 仍属 M4。

> **`termux-win-run.sh` 已停止维护**（文件保留，不再更新，也不建议使用）。
> 所有运行请直接在容器内使用 `win-run`。原因：它固定 `cwd=/tmp`、拒绝 Termux 私有目录，
> 并且与容器内的路径语义不一致；容器内的 `win-run` 现已支持 `--dir` + 相对路径。

## 用法

容器内（`termux-gui-attach.sh` 进入后）：

```bash
win-run app.exe
win-run app.exe arg1 "arg with spaces"
win-run --debug app.exe          # 打印架构/Prefix/后端证据
win-run --dir /tmp app.exe       # 指定工作目录
win-run -- app.exe --help        # 程序自身的选项
```

从 Termux 侧（**已停止维护**，仅作历史记录）：

```bash
# 旧的跨 chroot 包装器，不再维护
bash ~/bin/windows/termux-win-run.sh /tmp/win-tests/args_test.exe "a b" "中文"
```

现在请在容器内直接运行：

```bash
cd "/path/to/app dir" && win-run "app.exe"
win-run --dir "/path/to/app dir" "app.exe"
```

## PE 架构识别

`win-run` 直接解析 DOS Header → `e_lfanew` → `PE\0\0` → COFF `Machine` 字段，
不依赖 `file` 的文本输出：

| Machine | 架构 | 行为 |
|---|---|---|
| `0xAA64` | ARM64 | 原生 Wine |
| `0x8664` | AMD64 | 执行，由 Hangover 自动走 FEX |
| `0x014C` | I386 | 拒绝，提示属于 M3（退出码 3） |
| 其它 / 非 PE | — | 拒绝并报告（退出码 2） |

**不自行实现 FEX 分发器**：x64 走 `libarm64ecfex.dll` 是 Hangover 的行为，
`win-run` 只负责识别、启动与验证。

## FEX 证据

`win-run --debug` 会打印架构与后端说明；真正的证据来自运行日志：

```
starting FEX (Hangover 11.16) based libarm64ecfex.dll
```

M2 验收要求**必须出现这行**才算通过，只看退出码不算。

## 参数传递

- 容器内：`exec wine "$PROG" "$@"`，不做任何字符串拼接。
- 从 Termux 跨 chroot：不使用命令字符串，改为 **NUL 分隔参数文件**：
  1. Termux 侧把 `cwd` 和 `argv` 依次写入 `$PREFIX/tmp/termux-win-run/argv.XXXX`；
  2. `attach` 把该目录 bind 到容器 `/tmp/termux-win-run`；
  3. `win-run --argv-file` 用 `mapfile -d ''` 原样读回；
  4. 退出后删除文件。

这样空格、中文、引号都不会被 shell 二次解释。

## 工作目录

- 容器内调用：保持当前目录（即 shell 的 `pwd`）。
- 引号内的首尾空白会被去掉（复制粘贴路径常见）。`--dir DIR`：
  1. 校验 `DIR` 存在，并**规范成绝对路径**（允许 `--dir` 本身是相对路径、含空格）；
  2. 相对 EXE 按 `DIR` 解析；
  3. EXE 再做一次 `realpath` 规范化，去掉 `./`、`../` 和符号链接；
  4. 最后 `cd DIR` 并执行。

  ```bash
  win-run --dir "/home/pad/Office Tool" "Office Tool Plus.exe"
  win-run --dir "Office Tool" "./Office Tool Plus.exe"
  win-run --dir "Office Tool" "../Office Tool/files/setup.exe"
  ```

- 从 Termux 调用（旧包装器，已停止维护）：默认 `cwd=/tmp`。

## 环境继承

`win-run` 不重建环境，直接继承会话的 `DISPLAY`、`PULSE_SERVER`、
`MESA_LOADER_DRIVER_OVERRIDE`、`XDG_RUNTIME_DIR`、`LANG`、`WINEPREFIX`；
默认设置 `WINEDEBUG=-all`（需要时用环境变量覆盖）。

## 真机验收结果

| 测试 | 结果 |
|---|---|
| PE 架构识别（ARM64/AMD64/I386） | PASS |
| ARM64 Notepad | PASS（M1 延续） |
| AMD64 控制台程序 + 退出码 | PASS（`rc=7` 精确一致） |
| FEX 实际启动日志 | PASS（`starting FEX ... libarm64ecfex.dll`） |
| 参数保真（空格/中文/引号/中文 exe 名） | PASS |
| Z: 盘读写 | PASS |
| x64 GUI 窗口（输入框/按钮/关闭） | PASS |
| 多实例共享 wineserver | PASS（两窗口时 `wineserver=1`，关一个另一个仍在） |
| stop → start | PASS（wineserver 归零、全局挂载 0、重启后 `win-run` 正常） |
| `--debug` 诊断 | PASS |
| `--dir` | PASS |

### 启动耗时基线（真机，Adreno 610）

| 场景 | 耗时 |
|---|---|
| x64 控制台 冷启动 | 1957 ms |
| x64 控制台 热启动 | 132 ms / 84 ms |
| x64 GUI（程序自身活 3s）冷 | 5737 ms |
| x64 GUI（程序自身活 3s）热 | 3333 ms |

## 已知限制

1. **IA-32 未支持**：`win-run` 会明确拒绝并提示 M3。
2. **Wine Mono**：需要 .NET 的程序仍会提示安装 Mono，M2 不处理。
3. **无桌面菜单 / 文件关联**：M5 范围。
4. **DXVK 未启用**：M4 范围；当前图形走 WineD3D + KGSL OpenGL。
5. **中文输入法**：Wine 应用内的中文输入未测试。

## 排障

| 现象 | 原因 | 处理 |
|---|---|---|
| `Prefix 不可用` | 未安装 / 路径不对 | 先跑 `termux-win-install.sh` |
| `检测到 IA-32` | M3 范围 | 暂无正式支持 |
| 程序卡死 | `/dev/shm` 缺失 | 确认经 `termux-gui-start.sh` 启动会话 |
| `读不到参数文件` | Termux 侧目录不可读 | 确认 `attach` 已 bind `/tmp/termux-win-run` |

## EXE 路径语义（重要）

**传进去的 EXE 路径必须是“容器内可见”的路径**，不是 Termux 的路径。两者是不同的文件系统：

| 写法 | 含义 |
|---|---|
| `win-run /tmp/win-tests/app.exe` | 容器内的 `/tmp/...` |
| ~~`termux-win-run.sh /tmp/...`~~ | 已停止维护，不再使用 |

Termux 的 `$HOME`、`$PREFIX` 对容器用户不可见（目录是 `0700`），
因此 `termux-win-run.sh` 会检测并直接拒绝，而不是让用户看到误导性的“找不到文件”：

```
win-run: EXE 位于 Termux 私有目录，容器无法访问:
         /data/data/com.termux/files/home/xxx.exe
win-run: 请把它复制到容器可见路径（如容器内 /tmp/...），或放到共享存储后再试。
```

需要从 Termux 带文件进去时，先复制到容器可访问的位置，例如：

```bash
# Termux 侧
cp app.exe ~/../usr/tmp/termux-win-run/app.exe    # 该目录已 bind 到容器 /tmp/termux-win-run
bash ~/bin/windows/termux-win-run.sh /tmp/termux-win-run/app.exe
```

后续如需正式的“文件导入”功能，放到 M5 的产品化里做。

## 健壮性

### 参数文件清理

`termux-win-run.sh`（已停止维护的旧包装器）用 `trap cleanup EXIT` + `INT/TERM` 包住临时参数文件，
正常退出、Ctrl-C、`kill -TERM` 都会删除；实测三种情况的缓存目录都为空。

### 损坏 PE 的处理

`win-run` 会校验：`MZ` 标记 → `e_lfanew` 范围 → `PE\0\0` → `Machine`。
实测以下输入都返回退出码 2 和明确错误，而不是误判架构：

| 输入 | 结果 |
|---|---|
| 空文件 | 拒绝 |
| 文本文件（无 MZ） | 拒绝 |
| 有 PE 结构但被改掉 MZ | 拒绝 |
| `e_lfanew` 越界 | 拒绝 |
| 截断的 PE | 拒绝 |
| 正常 ARM64 / AMD64 / I386 | 正确识别 |

### `--debug` 与日志

`--debug` 打印的是**判定信息**（架构、Prefix、Wine 版本、后端说明）；
FEX 的真实证据来自运行日志里的这一行：

```
starting FEX (Hangover 11.16) based libarm64ecfex.dll
```

它输出到 stderr，`win-run` 不会自动保存日志；需要留存时请自行重定向，例如：

```bash
win-run --debug app.exe 2>&1 | tee /tmp/app.log
```

## 性能数据的读法

上表 GUI 数字包含**程序自身存活时间**（`--exit-after 3000`，即 3 秒），
所以 5.74 s ≈ 3 s + 2.7 s 启动与初始化，不能当作纯启动耗时。
---

## IA-32 支持（M3.1）

`I386` PE 现在直接走 Hangover 的 WoW64 路径，不需要额外参数：

```bash
win-run app32.exe            # 默认 WowBox64
HODLL=libwow64fex.dll win-run app32.exe   # 强制 FEX，做对照
```

`--debug` 会显示 IA-32 实际后端与应出现日志行：

```
  arch    : I386 (PE machine 0x14c)
  后端    : Box64 (wowbox64.dll)
  证据    : 运行日志中应出现 [BOX64] WowBox64 arm64 ...
```

### 真机验收（Hangover 11.16，正式 Prefix）

| 测试 | 结果 |
|---|---|
| I386 PE 识别并执行 | PASS |
| 退出码精确（返回 5 → rc=5） | PASS |
| 参数（空格/中文/引号） | PASS |
| Z: 盘读写 | PASS |
| Box64 日志证据 | PASS（`WowBox64 arm64 v0.4.4`） |
| FEX 覆盖 + 日志证据 | PASS（`starting FEX ... libwow64fex.dll`） |
| GUI 窗口 + 按钮回调 | PASS |
| 鼠标点击输入框、键盘输入、按钮触发 | PASS（用 `xdotool` 注入 X 事件，非物理触摸） |
| Unicode 窗口标题 | PASS（`_NET_WM_NAME = "ia32 中文标题 GUI"`） |
| Unicode 文本数据 | PASS（按钮读到 `hello ia32 guihello 中文 input`） |
| **Unicode 文本渲染** | **PARTIAL**：数据正确，但 EDIT 控件里中文显示为方框（缺字形） |
| 多实例（2 程序 1 wineserver） | PASS |
| stop/start 后可用 | PASS |
| ARM64 / AMD64 回归 | PASS |

### 已知问题：Wine 控件里的中文是方框

现象：标题栏（由 X 窗口管理器绘制）中文正常，但 Win32 `EDIT` 控件内的中文显示为 □□。
数据本身没问题（写文件、按钮读回都是正确的 UTF-8）。

已尝试但**无效**：

```bash
wine reg add "HKCU\\Software\\Wine\\Fonts\\Replacements" /v "Tahoma" /d "Noto Sans CJK SC" /f
# 对 MS Shell Dlg / Tahoma / Arial / Segoe UI / Microsoft Sans Serif 都设置过
```

容器里确实有中文字体（`fc-list :lang=zh` 非空），所以更可能是 Wine 默认 GUI 字体
没有回退到 CJK 字体，而不是字体缺失。后续可以尝试：

1. 在应用里用 `CreateFontW(L"Noto Sans CJK SC", ...)` 显式设置控件字体，验证字体是否可用；
2. 把 CJK 字体放进 `drive_c/windows/Fonts` 并在注册表登记；
3. 检查 Wine 的 `FontSubstitutes` 与 fontconfig 映射关系。

在解决之前，**中文 Windows 应用可能出现文字方框**，这是 M3.1 的已知限制。
# 12 · AMD64 Windows 运行时与统一入口 `win-run`（M2）

M2 只做两件事：给 Windows 程序一个统一入口，并正式支持 AMD64（经 Hangover 的 FEX）。
IA-32 仍属 M3，DXVK 仍属 M4。

## 用法

容器内（`termux-gui-attach.sh` 进入后）：

```bash
win-run app.exe
win-run app.exe arg1 "arg with spaces"
win-run --debug app.exe          # 打印架构/Prefix/后端证据
win-run --dir /tmp app.exe       # 指定工作目录
win-run -- app.exe --help        # 程序自身的选项
```

从 Termux 侧：

```bash
bash ~/bin/windows/termux-win-run.sh /tmp/win-tests/args_test.exe "a b" "中文"
WINRUN_DEBUG=1 bash ~/bin/windows/termux-win-run.sh app.exe
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

- 容器内调用：保持当前目录。
- 从 Termux 调用：Termux 的 `$HOME` 是 `0700`，容器用户无法进入，因此**默认 `cwd=/tmp`**，
  需要别的目录用 `--dir <容器内路径>`。这是明确行为，不是静默降级。

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

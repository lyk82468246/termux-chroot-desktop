# 三架构共存验证（M3.2）

日期：2026-11-09
环境：Hangover 11.16 / 单一 Prefix `~/.local/share/termux-chroot-desktop/wine/prefixes/default`

本阶段验证 ARM64、AMD64、I386 三种 Windows PE 能否**同时**跑在同一个 Wine Prefix、
同一个 wineserver 上，并且各自退出互不影响。

> 前提：M3.1 的已知问题「Wine 控件中文字符显示为方框」仍然存在（数据正确、渲染缺失），
> 不影响本阶段的 CPU 架构共存验证，单独作为遗留项处理。

## 1. 测试程序

| 架构 | 程序 | 说明 |
|---|---|---|
| ARM64 | `/usr/lib/wine/aarch64-windows/cmd.exe` | Wine 自带 ARM64 PE；`cmd /c exit N` 用于退出码 |
| ARM64（长驻） | `/usr/lib/wine/aarch64-windows/notepad.exe` | 用于"同时运行"场景 |
| AMD64 | `tests/windows/exit_test.c` → `exit_x64.exe` | 打印 `EXIT_TEST code=N`，返回 N |
| AMD64（长驻） | `tests/windows/gui_test.c` → 64 位 `gui_test.exe` | `--exit-after` 控制存活 |
| I386 | `exit_x86.exe`（`exit_test.c` 编译） | 返回 N |
| I386（长驻） | `tests/windows/ia32/gui32_test.c` → `gui_test.exe` | `--exit-after` 控制存活 |

**为什么 ARM64 不用自编译程序**：Ubuntu 26.04 仓库没有 aarch64-w64-mingw32 工具链，
本阶段用 Wine 自带的 ARM64 PE（`cmd.exe`/`notepad.exe`）作为 ARM64 代表，
并用 `win-run --debug` 的 `arch: ARM64 (PE machine 0xaa64)` 与"无 FEX/BOX64 日志"作为原生证据。

## 2. 独立运行 + 退出码（A）

| 架构 | 命令 | rc | 后端证据 |
|---|---|---|---|
| ARM64 | `win-run cmd.exe /c exit 3` | 3 | 无（原生，`starting FEX`/`[BOX64]` 计数为 0） |
| AMD64 | `win-run exit_x64.exe 5` | 5 | `starting FEX (Hangover 11.16) based libarm64ecfex.dll` |
| I386 | `win-run ia32/exit_x86.exe 7` | 7 | `[BOX64] WowBox64 arm64 v0.4.4` |

三个退出码 3/5/7 彼此不同，排除了串扰的可能。**PASS**

## 3. 三架构同时运行（B）

在同一 Prefix 中同时启动：

```
notepad.exe (ARM64) + gui_test.exe (AMD64) + ia32/gui_test.exe (I386)
```

实测：

```
三架构就绪: notepad=1 x64=1 x86=1 ws=1
```

- 三个进程同时存在：**PASS**
- 只有一个 wineserver：**PASS**
- 无 Prefix 锁冲突、无后端加载冲突：**PASS**

## 4. 独立退出（C）

### 顺序一：ARM64 → AMD64 → I386

| 操作 | 剩余进程 | wineserver |
|---|---|---|
| 关闭 ARM64 | x64=1 x86=1 | 1 |
| 关闭 AMD64 | x86=1 | 1 |
| 关闭 I386 | 无 | 0 |

### 顺序二：I386 → ARM64 → AMD64

| 操作 | 剩余进程 | wineserver |
|---|---|---|
| 关闭 I386 | np=1 x64=1 | 1 |
| 关闭 ARM64 | x64=1 | 1 |
| 关闭 AMD64 | 无 | 0 |

两种顺序都验证：单个程序退出不影响其他架构，wineserver 不会被提前杀死。**PASS**

## 5. 桌面生命周期（D）

```
stop  → wineserver=0, 全局 mounts=0
start → 三种架构再次运行：arm64_rc=3 amd64_rc=5 i386_rc=7
```

**PASS**

## 6. 异常情况（E）

| 场景 | 结果 |
|---|---|
| `kill -9` 其中一个 AMD64 程序 | ARM64 仍存活，wineserver=1（**PASS**） |
| 有程序运行时执行 `stop` | wineserver=0、全局 mounts=0（**PASS**） |
| stop 后重新 start | 三种架构退出码再次正确（**PASS**） |
| 不存在的 EXE | `win-run` 返回 2 并报"找不到文件"（M2.1 已验证） |

## 7. 结论

| 项目 | 结果 |
|---|---|
| ARM64 / AMD64 / I386 独立运行 | PASS |
| 三架构同时运行 | PASS |
| 单一 Prefix | PASS |
| 单一 wineserver | PASS |
| 独立退出（两种顺序） | PASS |
| 退出码 3/5/7 精确透传 | PASS |
| stop 清理（无残留 wineserver / 挂载 0） | PASS |
| restart 后三架构可用 | PASS |

至此三种 PE 架构已经能在一个 Prefix、一个 wineserver、一个 XFCE 会话中协同工作。

## 8. 未测试 / 遗留

1. **中文渲染方框**（M3.1 遗留）：数据通、标题通，控件字形缺失。
2. 三架构同时运行时的**音频**未测。
3. 长时间（小时级）共存稳定性未测。
4. 真实应用（安装器、复杂 GUI）未测。
5. ARM64 自定义测试程序缺失（无 aarch64-w64-mingw32 工具链）。

## 9. 复现

```bash
# 容器内
bash /tmp/win-tests/build.sh          # 64 位测试程序
bash /tmp/win-tests/ia32/build.sh     # 32 位测试程序
bash tests/windows/coexist.sh         # 三架构共存 + 两种退出顺序
```

# Windows 图形运行时（M4.1）

日期：2026-11-09
设备：Adreno 610 / Android 15 / Ubuntu 26.04 ARM64 chroot
运行时：Hangover 11.16（ARM64 / AMD64+FEX / I386+WowBox64）

本阶段把 **WineD3D** 确认为本设备受支持的默认 Direct3D 后端，并补齐 D3D9/D3D10/D3D11
在 AMD64 与 IA-32 两种架构下的真机验证。

**没有修改**正式 Prefix 的默认 DLL overrides，没有全局安装 DXVK DLL，
没有全局启用 `FD_DEV_FEATURES`，没有引入图形后端自动切换器。

## 1. 受支持的路径

| Windows API | 实现 | 状态 |
|---|---|---|
| D3D9 | WineD3D → OpenGL(FD610) | **PASS**（x64 + x86） |
| D3D10 | WineD3D → OpenGL(FD610) | **PASS**（x64 + x86） |
| D3D11 | WineD3D → OpenGL(FD610) | **PASS**（x64 + x86） |
| OpenGL | Mesa freedreno | PASS（`GL_RENDERER=FD610`） |
| DXVK | Vulkan | 不可用（缺 multiViewport，见 M4.0–M4.0.2） |
| D3D12 / VKD3D | — | NOT TESTED |

GPU 证据不是靠 DXGI 适配器名字（Wine 固定返回 `NVIDIA GeForce GTX 470` 这类假名），
而是：

```
GL_VENDOR=freedreno
GL_RENDERER=FD610
GL_VERSION=4.6 (Compatibility Profile) Mesa 27.0.0-devel (git-eb3e7fd4f0)
```

## 2. WineD3D 测试矩阵

测试程序源码：`tests/windows/graphics/`

| 程序 | 内容 |
|---|---|
| `d3d9_test.c` | 窗口 + `Direct3DCreate9` + 设备 + 清屏 + `DrawPrimitiveUP` 三角形 + `Present`（显式关闭光照，否则 D3D9 默认光照会让顶点色变黑） |
| `d3d10_test.c` | 窗口 + `D3D10CreateDeviceAndSwapChain` + 着色器 + 三角形 + `Present` |
| `d3d11_test.c` | 复用 M4.0 的 D3D11 测试（`../dxvk/d3d11_test.c`） |
| `gl_probe.c` | 在 Wine 进程内查询 `GL_VENDOR/GL_RENDERER/GL_VERSION` |

真机结果（正式 Prefix，`WINEDEBUG=-all`）：

| 程序 | 架构 | 后端日志 | 退出码 | 阶段日志 |
|---|---|---|---|---|
| `d3d9_x64.exe` | AMD64 | `starting FEX ... libarm64ecfex.dll` | 0 | DEVICE → FIRST_FRAME → TEST_COMPLETE |
| `d3d9_x86.exe` | I386 | `[BOX64] WowBox64 arm64 v0.4.4` | 0 | 同上 |
| `d3d10_x64.exe` | AMD64 | FEX | 0 | DEVICE → SWAPCHAIN → FIRST_FRAME → TEST_COMPLETE |
| `d3d10_x86.exe` | I386 | WowBox64 | 0 | 同上 |
| `d3d11_x64.exe` | AMD64 | FEX | 0 | feature_level=0xb000，同上 |
| `d3d11_x86.exe` | I386 | WowBox64 | 0 | feature_level=0xb000，同上 |

测试目录中不存在任何 DXVK DLL，也未设置 `WINEDLLOVERRIDES`，因此可以确认走的是 WineD3D。

**D3D9 彩色三角形截图**：`docs/images/d3d9-wined3d.png`
**D3D11 彩色三角形截图**：`docs/images/d3d11-wined3d.png`

## 3. GPU 诊断：`win-gpu-diagnose`

安装位置：`~/bin/windows/win-gpu-diagnose`（`install.sh` 随 `scripts/windows/` 一起部署）。

用法：

```bash
win-gpu-diagnose
GL_PROBE=/path/gl_probe_x64.exe win-gpu-diagnose
```

实测输出（摘要）：

```
Wine                   wine-11.16 (Hangover)
hangover-wine          11.16~resolute
hangover-wowbox64      11.16
hangover-libwow64fex   11.16
libvulkan1             1.4.341.0-1
mesa-vulkan-drivers    26.0.3-1ubuntu1

GL_VENDOR=freedreno
GL_RENDERER=FD610
GL_VERSION=4.6 (Compatibility Profile) Mesa 27.0.0-devel (git-eb3e7fd4f0)

deviceName = Turnip Adreno (TM) 610
driverName = turnip Mesa driver
apiVersion = 1.3.363
Vulkan: multiViewport=false
Vulkan: maxViewports=1

DLL overrides: 无（默认）
结论: WineD3D → OpenGL，本设备受支持路径
FD_DEV_FEATURES: 未设置（正确）
```

诊断脚本只读，不修改任何配置。

## 4. DXVK 状态（保留实验资料）

- DXVK 2.7.1 能加载并识别 Turnip，但因 `multiViewport=false` 拒绝设备（M4.0）。
- `FD_DEV_FEATURES=has_hw_multiview=1` 能强行打开 feature，但非零 `ViewportIndex`
  的路由错误（M4.0.1 / M4.0.2）。
- 因此 **DXVK 不是本设备的受支持路径**；不要在启动脚本中设置该环境变量。
- 单 viewport 程序在强制开启时可运行，但属于开发者实验，不能作为兼容性承诺。

## 5. 已知限制

1. **中文控件方框**：数据通、标题通，Wine 控件字形缺失（M3.1 遗留，独立问题）。
2. **D3D12 / VKD3D**：未验证。
3. **性能**：本阶段只验证正确性，未做帧率/功耗测量。
4. **复杂应用**：仅用自写测试程序验证，未覆盖真实游戏/安装器。
5. **DXVK**：受 Adreno 610 + Turnip 的 multiViewport 限制，不可用。

## 6. 回归

| 项目 | 结果 |
|---|---|
| ARM64 Notepad 启动 | PASS |
| AMD64 Win32 GUI（`GUI_BUTTON`） | PASS |
| IA-32 Win32 GUI（`GUI_BUTTON`） | PASS |
| AMD64 D3D11 | PASS |
| IA-32 D3D11 | PASS |
| IA-32 D3D9 | PASS |
| stop → 全局 mounts=0、wineserver=0 | PASS |
| start → 三架构程序再次可用 | PASS |

## 7. 复现

```bash
# 容器内构建
bash /tmp/win-tests/graphics/build.sh
# 运行（WineD3D，无 DXVK）
WINEPREFIX=... win-run /tmp/win-tests/graphics/d3d9_x64.exe --frames 10
```

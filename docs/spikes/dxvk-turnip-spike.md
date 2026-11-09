# DXVK + Turnip Spike（M4.0）

日期：2026-11-09
设备：Lenovo TB331FC / Adreno 610 / Android 15 / KernelSU
环境：Ubuntu 26.04 ARM64 chroot + Hangover 11.16 + 单一正式 Prefix

本阶段目标：验证现有 Turnip Vulkan 环境能否让 **AMD64 Windows D3D11 程序经 DXVK** 在 Adreno 610 上硬件渲染。
**不修改**正式 Prefix 的默认图形配置，不覆盖系统 DLL，不替换 Mesa/Turnip。

## 1. Vulkan 环境审计（容器内、pad 身份）

| 项 | 值 |
|---|---|
| loader | `libvulkan.so.1`（容器内） |
| ICD | `/usr/share/vulkan/icd.d/freedreno_icd.aarch64.json` 等多套 |
| deviceName | `Turnip Adreno (TM) 610` |
| deviceType | `PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU` |
| driverName | `turnip Mesa driver` |
| driverInfo | `Mesa 27.0.0-devel (git-eb3e7fd4f0)` |
| apiVersion | `1.3.363` |
| `VK_KHR_swapchain` | 可用（vulkaninfo 中出现 9 次） |
| llvmpipe 对照 | `llvmpipe (LLVM 21.1.8, 128 bits)` 也存在 |

**PASS**

## 2. DXVK 资产

| 项 | 值 |
|---|---|
| 文件 | `dxvk-v2.7.1.tar.gz`（16,475,867 字节） |
| SHA-256 | `36be8b5803d800abc3f707e36256c77b374a108d73c03a7e34fb42b5f71be8aa`（与 M1 记录一致） |
| 结构 | `dxvk-v2.7.1/{x64,x86,aarch64}/` 下含 `d3d8/d3d9/d3d10core/d3d11/dxgi.dll` |

**PASS**

## 3. D3D11 测试程序

`tests/windows/dxvk/d3d11_test.c`（MinGW-w64 x86_64 编译，PE `0x8664`）：

- 创建窗口 → `D3D11CreateDeviceAndSwapChain`（hardware）→ 编译 HLSL（`D3DCompile`）→
  画一个 RGB 三角形 → `Present` → 循环 `--frames N`。
- 阶段日志：`WINDOW_CREATED` / `D3D11_DEVICE_CREATED` / `SWAPCHAIN_CREATED` /
  `GPU_ADAPTER` / `FIRST_FRAME_RENDERED` / `TEST_COMPLETE` / `D3D11_FAIL`。

### WineD3D 基线（未启用 DXVK）

```
WINDOW_CREATED
D3D11_DEVICE_CREATED feature_level=0xb000
SWAPCHAIN_CREATED
GPU_ADAPTER=NVIDIA GeForce GTX 470 vendor=0x10de   # Wine 的固定假名，不能当证据
FIRST_FRAME_RENDERED
TEST_COMPLETE frames=30
rc=0  elapsed=6013ms
```

渲染截图为实心彩色三角形（见 `docs/images/d3d11-wined3d.png`）。
Wine 的 OpenGL 渲染器此前已实测为 `FD610`（非 llvmpipe），所以 WineD3D 走的是**真实 GPU OpenGL**。

**PASS**

## 4. DXVK 实际加载（关键结果）

把 DXVK 的 x64 DLL 放在**测试程序所在目录**，用
`WINEDLLOVERRIDES=d3d11,dxgi,d3d10core,d3d9=native` 加载，
不修改正式 Prefix、不覆盖系统文件。

DXVK 能启动并枚举设备，但**拒绝了 Turnip**：

```
info:  DXVK: v2.7.1-4-g2c50a56
info:  Found device: Turnip Adreno (TM) 610 (turnip Mesa driver 26.99.99)
info:    Skipping: Device does not support required feature 'multiViewport'
info:  Found device: llvmpipe (LLVM 21.1.8, 128 bits) (llvmpipe 26.0.3)
info:    Skipping: Software driver
warn:  DXVK: No adapters found.
err:   D3D11CreateDevice: Failed to create a DXGI factory
```

程序侧结果：

```
WINDOW_CREATED
D3D11_FAIL stage=d3d11_create hr=0x80004005
dxvk_rc=3
```

### 根因确认

`vulkaninfo` 中该设备的 VkPhysicalDeviceFeatures：

```
multiViewport = false     # 第 1387 行（Turnip 设备）
```

DXVK 把 `multiViewport` 当作**硬性要求**（D3D11 viewport 数组），不满足即跳过适配器。

### 尝试过的规避（均无效）

| 尝试 | 结果 |
|---|---|
| `dxvk.conf: dxvk.enableMultiViewport = False` | 配置被识别（Effective configuration 有该行），但适配器检查仍要求该特性 |
| 只保留 x64 DLL、不加载 d3d9/d3d10 | 与后端无关，仍被跳过 |
| 强制 `VK_ICD_FILENAMES=freedreno` | 同一设备，同一结论 |

**FAIL（硬件 DXVK）**

## 5. 对照实验：DXVK 在 llvmpipe 上可用

为区分"DXVK/测试程序有问题"与"驱动缺特性"，强制软件 ICD：

```
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json
dxvk.conf: dxvk.allowSoftware = True
```

结果：

```
info:  Found device: llvmpipe (LLVM 21.1.8, 128 bits)
SWAPCHAIN_CREATED
FIRST_FRAME_RENDERED
TEST_COMPLETE frames=5
rc=0
```

**PASS** —— 证明 DXVK 2.7.1 与测试程序本身正常，唯一的阻塞点是 Turnip 缺少 `multiViewport`。

## 6. 结论

| 项目 | 结果 |
|---|---|
| Vulkan 环境（Turnip 1.3 / Adreno 610） | PASS |
| DXVK 资产与哈希 | PASS |
| D3D11 测试程序（WineD3D / GPU OpenGL） | PASS |
| DXVK 加载与设备枚举 | PASS（能看到 Turnip） |
| **DXVK + Turnip 硬件渲染** | **FAIL / BLOCKED**：`multiViewport=false` |
| DXVK 在软件 Vulkan 上工作 | PASS（对照实验） |
| 修改正式 Prefix | 未修改 |
| 覆盖系统 DLL | 未发生 |

**M4.1 正式集成 DXVK 的前置条件**（任一满足才可继续）：

1. 更新/更换 Turnip 构建，使 Adreno 610 暴露 `multiViewport`；
2. 或有 DXVK 变体/补丁在缺少 `multiViewport` 时仍能初始化（需上游支持，不能本地魔改）；
3. 或明确把 D3D11 支持限定为 **WineD3D（OpenGL）**，DXVK 仅用于具备该特性的设备。

当前可用的 D3D11 硬件路径是 **WineD3D → OpenGL(FD610)**，已实测渲染成功。

## 7. 未测试 / 限制

- DXVK + **x86 (I386)**：M4.0 先做 x64；未测。
- D3D9 / D3D10 / D3D12（VKD3D）：未测。
- DXVK 与 WineD3D 的性能对比：无硬件 DXVK，无法比较。
- 长时间运行、温度、降频：未测。
- 中文渲染方框（M3.1 遗留）与图形无关，仍存在。

## 8. 复现

```bash
# 容器内
bash /tmp/win-tests/dxvk/build.sh
# WineD3D
WINEPREFIX=... win-run /tmp/win-tests/dxvk/d3d11_test.exe --frames 30

# DXVK（硬件，预期失败）
cd /tmp/win-tests/dxvk/run
WINEDLLOVERRIDES=d3d11,dxgi,d3d10core,d3d9=native DXVK_LOG_LEVEL=info \
  win-run d3d11_test.exe --frames 5

# DXVK（软件对照，预期成功）
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json DXVK_CONFIG_FILE=... \
  win-run d3d11_test.exe --frames 5
```

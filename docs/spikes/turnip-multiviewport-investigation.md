# Turnip multiViewport 能力调查（M4.0.1）

日期：2026-11-09
设备：Lenovo TB331FC / Adreno 610 / Android 15 / KernelSU
环境：Ubuntu 26.04 ARM64 chroot + Hangover 11.16 + Mesa 27.0.0-devel（Turnip）

M4.0 结论是 DXVK 因 `multiViewport=false` 拒绝 Turnip。本阶段回答一个更精确的问题：
**这是"硬件不支持"、"驱动没实现"，还是"只是配置保守"？**

## 1. Mesa 源码审计

拉取上游 `src/freedreno/common/freedreno_devices.py`（2026-11 版本，61 KB）核对：

```python
a6xx_base = GPUProps(
        ...
        has_hw_multiview = True,
        ...)

a6xx_gen1_low = GPUProps(
        ...
        has_gmem_fast_clear = False,
        has_hw_multiview = False,      # ← 低端 A6xx 子系列
        ...)
```

Adreno 610 被明确归入 `a6xx_gen1_low`：

```python
add_gpus([ GPUId(605), GPUId(608), GPUId(610), GPUId(612), ... ],
         A6xxGPUInfo(CHIP.A6XX, [a6xx_base, a6xx_gen1_low], ...))
```

即：`has_hw_multiview` 从基类 `True` 被**子系列覆盖为 False**。这与之前查到的
Mesa 提交说明（"Leave the optional multiViewport feature disabled, matching the blob driver"）一致。

同时源码注释确认存在运行时覆盖机制：

```python
# Props could be modified with env var:
#  FD_DEV_FEATURES=%feature_name%=%value%:%feature_name%=%value%:...
```

**PASS（源码结论清晰）**

## 2. FD_DEV_FEATURES 实验

只对单个测试进程设置环境变量，不写任何全局配置：

| 查询项 | 默认 | `FD_DEV_FEATURES=has_hw_multiview=1` |
|---|---|---|
| `multiViewport` | **false** | **true** |
| `maxViewports` | **1** | **16** |
| `VK_EXT_shader_viewport_index_layer` | 不存在 | 存在 |

说明 Turnip 的能力表确实可被运行时改写，且这一项同时打开了 viewport 数组与
shader 选择 viewport 的扩展。

**PASS（覆盖生效）**

## 3. 原生 Vulkan 多视口测试（关键实验）

新增 `tests/windows/dxvk/vulkan-multiviewport/vulkan_mv.c`（Linux ARM64 原生程序）：

- 创建离屏 64×64 图像；
- 图形管线配置 **两个 viewport**（左半 / 右半），scissor 同步；
- 顶点着色器用 `gl_ViewportIndex = gl_InstanceIndex`，两实例分别画红/绿三角形；
- 渲染后 `vkCmdCopyImageToBuffer` 回读，检查左右像素颜色。

结果：

| 场景 | 特性 | 管线 | 左像素 | 右像素 | 判定 |
|---|---|---|---|---|---|
| 默认 Turnip | false | 未创建 | — | — | UNSUPPORTED（预期） |
| **强制 `has_hw_multiview=1`** | true | **创建成功** | `(0,255,0)` 绿 | `(0,0,0)` 黑 | **FAIL** |
| llvmpipe（对照） | true | 创建成功 | `(255,0,0)` 红 | `(0,255,0)` 绿 | **PASS** |

强制开启后的现象非常明确：**两个实例的三角形都画到了 viewport 0**，
`gl_ViewportIndex` 被忽略，右侧 viewport 完全没有内容。

llvmpipe 对照证明测试程序本身正确（左红右绿）。

**结论：Turnip 在 Adreno 610 上只是"敢声明"，并没有正确实现 viewport 索引路由。**

## 4. DXVK 强制复测

带着 `FD_DEV_FEATURES=has_hw_multiview=1` 重跑 DXVK 2.7.1 + D3D11 测试：

```
info:  Found device: Turnip Adreno (TM) 610 ...
info:    multiViewport                  : 1
WINDOW_CREATED
D3D11_DEVICE_CREATED feature_level=0xb000
SWAPCHAIN_CREATED
FIRST_FRAME_RENDERED
TEST_COMPLETE frames=10
GPU_ADAPTER=Turnip Adreno (TM) 610 vendor=0x5143
```

截图显示三角形渲染正常（单 viewport 场景）。

**PARTIAL**：DXVK 确实能在 Adreno 610 上初始化并渲染，但这是建立在
**违反 feature 语义**的基础上——任何真正使用多 viewport 的 D3D11 应用都会渲染错误。

## 5. Qualcomm 官方驱动对照

**NOT TESTED**：当前环境没有 Android 侧的 Vulkan 能力查询工具，
无法在不替换日常驱动的前提下读取 blob 驱动的 `multiViewport`。
Mesa 提交说明其行为与 blob 一致，但本机未取得独立证据。

## 6. Vulkan CTS

**NOT TESTED**：未安装 Vulkan CTS（体积与构建成本过高），
本阶段用自写像素级测试代替；结论已足以判定"声明与实现不符"。

## 7. 结论分类

按任务给定的四类：

- **A. 硬件明确不支持**：不能断言。寄存器层面存在 `GRAS_CL_VIEWPORT_ZCLAMP` 等资源，
  但"存在状态寄存器" ≠ "完整支持 viewport index 路由"。
- **B. 硬件可能支持，但驱动未实现**：**最符合证据**。
  Turnip 在强制声明后无法正确路由 viewport index，Mesa 因此保守关闭并与 blob 对齐。
- **C. 驱动支持、当前构建有问题**：不成立。强制打开后不是"能用但慢"，而是渲染结果错误。
- **D. 证据不足**：不适用，已有像素级反证。

**最终判定：B（驱动未实现 / 硬件能力不足以支撑完整语义）。
Mesa 的 `has_hw_multiview=False` 是有依据的保守选择，不是遗漏。**

## 8. 对 M4 路线的影响

1. **不要把 `FD_DEV_FEATURES` 写进任何启动脚本**：它会让 DXVK "看起来能用"，
   但多 viewport 应用会静默渲染错误，比直接失败更危险。
2. **WineD3D 应作为本设备的正式 D3D9/10/11 路径**（M4.0 已证明 GPU OpenGL 渲染正常）。
3. **DXVK 在本设备仅作为实验选项**：单 viewport 应用可尝试，需显式文档说明风险；
   正式启用门槛应为：
   - 驱动 `multiViewport=true` 且 `maxViewports>1`；
   - **原生多视口像素测试通过**（本阶段的 `vulkan_mv` 可作为回归用例）。
4. 除非换设备/换驱动，**升级 Mesa 版本不会改变结论**（上游已明确与 blob 对齐）。

## 9. PASS / FAIL / PARTIAL / NOT TESTED

| 项目 | 结果 |
|---|---|
| Mesa 源码设备分类审计 | PASS |
| FD_DEV_FEATURES 覆盖生效 | PASS |
| 默认 Turnip 的 multiViewport 状态 | PASS（false，符合源码） |
| 强制开启后的原生多视口渲染 | **FAIL**（像素错误） |
| llvmpipe 对照 | PASS |
| DXVK + 强制 feature 初始化 | PASS |
| DXVK + 强制 feature 正确性 | **PARTIAL / 不可信**（多 viewport 语义被破坏） |
| 官方 blob 驱动对照 | NOT TESTED |
| Vulkan CTS | NOT TESTED |

## 10. 复现

```bash
# 构建
bash tests/windows/dxvk/vulkan-multiviewport/build.sh
# 默认（预期 UNSUPPORTED）
./vulkan_mv Turnip
# 强制覆盖（预期 FAIL：左绿右黑）
FD_DEV_FEATURES=has_hw_multiview=1 ./vulkan_mv Turnip
# 对照（预期 PASS）
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json ./vulkan_mv llvmpipe
```

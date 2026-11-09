# ViewportIndex 失效机理定位（M4.0.2）

日期：2026-11-09
设备：Adreno 610 / Android 15 / Ubuntu 26.04 ARM64 chroot
驱动：Mesa 27.0.0-devel Turnip，Vulkan 1.3.363

M4.0.1 已证明：强制 `FD_DEV_FEATURES=has_hw_multiview=1` 后 feature 变 true，
但双 viewport 渲染结果错误。本阶段把错误定位到具体环节。

## 1. 测试方法

在 `tests/windows/dxvk/vulkan-multiviewport/` 中新增三种着色器路径，
统一用离屏 64×64 + 像素回读判定：

| 模式 | 着色器 | 预期（若语义正确） |
|---|---|---|
| `vs0` | VS：`gl_ViewportIndex = 0` | 两个实例都进左视口 → 左绿、右黑 |
| `vs1` | VS：`gl_ViewportIndex = 1` | 两个实例都进右视口 → 左黑、右绿 |
| `vsdyn` | VS：`= gl_InstanceIndex` | 左红、右绿 |
| `gs1` | VS 透传 + **GS**：`gl_ViewportIndex = 1` | 左黑、右绿 |

同时修正了测试程序的同步问题：

- 回读内存改为 `HOST_VISIBLE | HOST_COHERENT`，并在 `vkMapMemory` 后显式
  `vkInvalidateMappedMemoryRanges`；
- 渲染通道结束后、`vkCmdCopyImageToBuffer` 前增加
  `COLOR_ATTACHMENT_OUTPUT → TRANSFER` 的显式 memory barrier。

## 2. 结果矩阵

| 场景 | 设备/条件 | 左像素 | 右像素 | 语义判定 |
|---|---|---|---|---|
| `vs0` | Turnip 强制 | (0,255,0) | (0,0,0) | 正确（index 0） |
| **`vs1`** | Turnip 强制 | (0,255,0) | (0,0,0) | **错误**：应左黑右绿 |
| `vsdyn` | Turnip 强制 | (0,255,0) | (0,0,0) | **错误**：应左红右绿 |
| **`gs1`** | Turnip 强制（已启用 geometryShader） | (0,255,0) | (0,0,0) | **错误**：GS 的 index 1 也被忽略 |
| `vsdyn` | Turnip 默认 | — | — | UNSUPPORTED（预期） |
| `vs0` | llvmpipe | (0,255,0) | (0,0,0) | 正确 |
| `vs1` | llvmpipe | (0,0,0) | (0,255,0) | 正确 |
| `vsdyn` | llvmpipe | (255,0,0) | (0,255,0) | 正确 |
| `gs1` | llvmpipe | (0,0,0) | (0,255,0) | 正确 |

**关键观察**：Turnip 上无论是**常量 1**、**动态值**还是 **Geometry Shader 输出**，
结果都是"全部画进 viewport 0"。只有 index 0 恰好看起来正确。

## 3. SPIR-V 正确性

`spirv-dis` 检查 `vert1.spv`：

```
OpCapability ShaderViewportIndexLayerEXT
OpDecorate %gl_ViewportIndex BuiltIn ViewportIndex
%gl_ViewportIndex = OpVariable %_ptr_Output_int Output
```

即着色器确实声明并写出了 `ViewportIndex`，llvmpipe 用同一份 SPIR-V 能正确路由。
所以**不是 SPIR-V 生成问题，也不是测试程序问题**。

## 4. 结论

按任务给定的四类：

- A. Shader 编译器问题 → **不能完全排除**：llvmpipe 与 Turnip 使用不同的 NIR/IR3 后端，\n  同一份 SPIR-V 在 llvmpipe 上正确，只能排除 GLSL/SPIR-V 生成问题，不能排除 Turnip 的\n  NIR 降低或 IR3 指令生成问题。
- B. Turnip 驱动实现问题 → **部分成立但未定位到具体函数**：
  我们只能看到"index 被忽略"，没有 IR3 反汇编/debug build 来确认是 NIR 降低、
  viewport 状态编程，还是硬件路由。
- **C. 硬件动态 viewport 路由不可用 → 最符合证据。**
  证据：常量 1 与 GS 输出 1 都被忽略；仅当 index=0 时结果碰巧正确；
  Mesa 上游选择关闭该 feature 并与 blob 对齐。
- D. 无法定位 → 不成立，已排除测试程序与编译器。

**最终判定：C（硬件/驱动层的 viewport index 路由不可用）。
继续用环境变量或升级 Mesa 不会解决；Mesa 的 `has_hw_multiview=False` 是正确取舍。**

## 5. 对 DXVK 的意义

1. DXVK 的 `multiViewport` 是硬性能力要求，不是可选优化；
2. 强制声明只能骗过初始化，遇到任何真正使用多 viewport 的 D3D11 应用会**静默画错**；
3. 完整 DXVK 支持需要：
   - 软件模拟多视口（shader 改写 / 拆分 draw），工程量大且语义复杂（深度、模板、
     Query、Stream Output、scissor 都要正确处理）；或
   - 更换具备真实 multiViewport 的设备/驱动。

## 6. PASS / FAIL / PARTIAL / NOT TESTED

| 项目 | 结果 |
|---|---|
| 测试程序同步修正 | PASS |
| 常量 0 路径 | PASS（正确） |
| 常量 1 路径 | **FAIL（Turnip）** / PASS（llvmpipe） |
| 动态 viewport index | **FAIL（Turnip）** / PASS（llvmpipe） |
| Geometry Shader 输出 index | **FAIL（Turnip）** / PASS（llvmpipe） |
| SPIR-V 含 BuiltIn ViewportIndex | PASS |
| IR3 / NIR 反汇编定位 | NOT TESTED（无 Mesa debug 构建） |
| Vulkan CTS | NOT TESTED |
| 官方 blob 对照 | NOT TESTED |

## 7. 复现

```bash
bash tests/windows/dxvk/vulkan-multiviewport/build.sh
cd tests/windows/dxvk/vulkan-multiviewport
FD_DEV_FEATURES=has_hw_multiview=1 ./vulkan_mv Turnip vs1   # 预期：左绿右黑（错误）
FD_DEV_FEATURES=has_hw_multiview=1 ./vulkan_mv Turnip vs0   # 预期：左绿右黑（正确）
VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json ./vulkan_mv llvmpipe vs1  # 预期：左黑右绿
```

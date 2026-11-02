# 02 · GPU 加速：为什么必须是 KGSL 后端

这一章讲清楚一件事：**为什么在这台设备上，标准 Mesa 永远拿不到 3D，而 KGSL 后端可以。**

## 第一直觉：有 `/dev/dri` 就能用 GPU？

在 Android 上 `ls /dev/dri` 经常能看到 `card0` 和 `renderD128`，看起来一切正常：

```
crw-rw-rw- 1 root graphics 226,   0 card0
crw-rw-rw- 1 root graphics 226, 128 renderD128
```

但查一下这个 DRM 设备到底是什么：

```bash
cat /sys/class/drm/renderD128/device/uevent
# DRIVER=msm_drm
# OF_NAME=qcom,mdss_mdp
# OF_COMPATIBLE_0=qcom,sde-kms
```

`mdss_mdp` / `sde-kms` 是**显示控制器**（KMS 输出、图层合成），不是 3D 引擎。再查内核配置：

```bash
zcat /proc/config.gz | grep DRM_MSM   # CONFIG_DRM_MSM is not set
ls /sys/module | grep kgsl            # msm_kgsl
cat /sys/class/kgsl/kgsl-3d0/gpu_model  # Adreno610v26
```

结论很清楚：

- 3D 引擎由高通的私有驱动 **KGSL**（`/dev/kgsl-3d0`）接管
- 主线 DRM 的 `msm`（freedreno 依赖的那个）根本没编进内核
- 因此 **freedreno / turnip 无法通过 DRM 路径工作**

## 第二直觉：那能不能让 Mesa 直接说 KGSL？

可以。这是 Lucas Fryzek 的 [KGSL 后端 MR](https://gitlab.freedesktop.org/mesa/mesa/-/merge_requests/21570) 做的事：给 freedreno 增加一个 KGSL 的 KMD（内核态驱动）后端，让它绕开 DRM 直接与 `/dev/kgsl-3d0` 通信。

现成的构建由 [lfdevs/mesa-for-android-container](https://github.com/lfdevs/mesa-for-android-container) 提供，按发行版打包，正是为 PRoot/Chroot 场景准备的。

装好之后加一个环境变量即可切换：

```bash
export MESA_LOADER_DRIVER_OVERRIDE=kgsl
```

## 验证

```bash
MESA_LOADER_DRIVER_OVERRIDE=kgsl eglinfo | head -20
```

期望输出：

```
EGL driver name: kgsl
OpenGL core profile renderer: FD610
OpenGL core profile version: 4.6 (Core Profile) Mesa 27.0.0-devel
OpenGL ES profile renderer: FD610
```

`FD610` 就是 Adreno 610 在 freedreno 里的设备标识。`MESA-LOADER: failed to retrieve device information` 那行是无害的——Mesa 先试 DRM 失败，随后按环境变量回落到 KGSL。

## 性能基准

```bash
MESA_LOADER_DRIVER_OVERRIDE=kgsl glmark2-es2 -s 640x480
```

实测（Adreno 610，6 核）：

| 场景 | FPS |
|---|---|
| `[build] use-vbo=true` | 1010 |
| `[texture] nearest` | 997 |
| `[shading] phong` | 991 |
| `[desktop] blur x4` | 687 |
| `[buffer] subdata` | 261 |

瓶颈在顶点上传（`buffer` 场景），符合单 CCU 低端 a6xx 的特征；日常桌面合成、浏览器、视频都绰绰有余。

## 注意事项

1. **不要用 `apt upgrade` 覆盖 Mesa**。系统更新会把 KGSL 版换回官方版，表现为 `renderer` 变回 `llvmpipe`。
   ```bash
   apt-mark hold libegl-mesa0 libgbm1 libgl1-mesa-dri libglx-mesa0 mesa-libgallium mesa-vulkan-drivers
   ```
2. **不同发行版用不同的包**。Ubuntu 24.04 用 `ubuntu_noble_arm64`，26.04 用 `ubuntu_resolute_arm64`，混用会因 glibc/ABI 差异出问题。
3. **Vulkan 也可用**（turnip），但低端 6xx 上 OpenGL 路径更稳。

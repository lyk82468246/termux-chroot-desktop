# 03 · 白屏之谜：合成器的 A/B 实验

这是整个项目里最磨人的一段。症状很怪：**桌面连上了，进程都在跑，但屏幕是纯白的**，而且鼠标指针会变形状（说明 X 侧的窗口确实存在）。

## 症状清单

| 观察 | 含义 |
|---|---|
| `direct rendering: Yes`，`renderer: FD610` | GPU 正常 |
| 容器内 47 个 Xfce 进程全部存活 | 桌面起来了 |
| 屏幕纯白，但指针形状会随窗口变化 | X 服务在跑、窗口存在 |
| `xmessage` 单独跑能显示，起桌面后就不能 | 不是客户端问题 |

## 排除法：逐个组件验证

先确认渲染链路本身没问题——在只有 X 服务的情况下跑最小客户端：

```bash
xmessage -geometry 700x250 "hello"     # ✅ 正常显示
glxgears                                # ✅ 90 FPS，齿轮正常
xfdesktop                               # ✅ 壁纸和桌面图标正常
xfce4-panel                             # ✅ 面板正常
xfwm4                                   # ❌ 一启动就白屏
```

到这里已经锁定了：**`xfwm4`**。

## A/B 实验

用「白色像素占比」做客观指标（`white_ratio > 0.5` 即判定为白屏），同一套流程各跑两次：

| 试验 | 合成 | white_ratio | mean_luma | 结果 |
|---|---|---|---|---|
| on-1 | 开 | **0.905** | 232.6 | 白屏 |
| off-1 | 关 | **0.010** | 58.8 | 正常 |
| on-2 | 开 | **0.905** | 232.6 | 白屏 |
| off-2 | 关 | **0.010** | 58.8 | 正常 |

两次结果**逐位相同**，确定性成立。

## 那换个合成器呢？

`picom` 有三种后端，挨个测：

| 方案 | 后端 | 结果 | luma |
|---|---|---|---|
| xfwm4 内置合成 | GLX → kgsl | ❌ 白屏 | 232.6 |
| picom `--backend glx` | GLX → kgsl | ❌ 黑屏 | 3.5 |
| picom `--backend xrender` | XRender（CPU） | ✅ 正常 + 阴影 | 59.0 |
| 无合成 | — | ✅ 正常 | 58.8 |

**关键结论：两个独立的合成器，只要走 GLX 就都坏。** 所以问题不在 xfwm4，而在「GLX 合成 + Xlorie」这个组合——大概率是 Xlorie 对合成所需的离屏 pixmap / damage 处理不完整，导致应用的画面缓冲停止更新。

## 为什么杀掉 xfwm4 画面不会恢复

这一点曾经让人误判。合成器退出后，没有任何进程再触发重绘，Xlorie 会继续显示**上一帧**（那帧正好是白色清屏）。所以「关掉合成」必须在**启动前**生效，事后补救无效。

## 中间踩过的三个坑

### 坑 1：陈旧 socket 让应用连到死掉的服务端

`/data/data/com.termux/files/usr/tmp/.X11-unix/X0` 是普通文件系统里的 socket，**重启不会清理**。服务端崩溃后 socket 残留，Termux:X11 应用连上去会一直显示 `Not connected`。

排查方法：

```bash
ls -l $PREFIX/tmp/.X11-unix/     # 有 X0 但没有对应进程 = 僵尸
```

脚本里现在会在启动前清理：

```bash
[[ -S $XSOCK ]] && warn "发现残留 socket（服务已死），清理后重启"
rm -f "$XSOCK" "$PREFIX/tmp/.X0-lock"
```

而且判断 X 服务存活必须**同时**满足「socket 存在」和「进程活着」。

### 坑 2：X 进程的名字在 `comm` 里，不在 `cmdline` 里

`termux-x11` 是用 `app_process --nice-name` 启动的，`/proc/pid/comm` 显示的是 `main`，真正可识别的字符串只在 `cmdline`：

```
termux-x11 com.termux.x11 :0 -ac -dpi 160
```

所以进程检测要扫 `cmdline`，不能只看 `comm`。

### 坑 3：`TMPDIR` 被子环境污染

X 服务会在 `$TMPDIR` 里建锁文件。如果 `TMPDIR` 被继承成了 `/data/local/tmp`，它会去 `/tmp` 建锁并失败：

```
Fatal server error: Could not create lock file in /tmp/.tX0-lock
```

修复：脚本里强制 `export TMPDIR="$PREFIX/tmp"`，不要用 `${TMPDIR:-...}` 保留继承值。

## 最终方案

默认**关闭合成**（最稳、最省电）；需要阴影时用 `COMPOSITOR=picom`，脚本会启动 `picom --backend xrender`，它在私有命名空间里运行，不影响桌面会话。

CPU 开销实测（glxgears 持续重绘 5 秒采样）：

| 方案 | CPU |
|---|---|
| picom xrender | 3.4% |
| xfwm4 + `LIBGL_ALWAYS_SOFTWARE=1` | 4.4% |
| 无合成 | ≈0% |

xfwm4 的软件 GL 方案虽然也能用，但它依赖环境变量注入，而 `xfce4-session` 的会话恢复会把包装脚本绕过（实测被绕回 GLX 路径，白屏 + 20% CPU 空转）。**picom 是独立进程，不受会话管理干预，更可靠。**

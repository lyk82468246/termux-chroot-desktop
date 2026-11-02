# 04 · 挂载安全：一次 789 个挂载的事故复盘

这一章记录一次真实事故，以及为什么本项目的所有挂载都要包在**私有命名空间 + 前置校验**里。

## 事故经过

为了把 X11 的 socket 和 `/dev` 暴露给 chroot，早期脚本这样写：

```bash
unshare -m sh -c "
  mount -t proc proc $D/proc
  mount --bind /dev $D/dev
  ...
"
```

看起来没问题，`unshare -m` 明明创建了新命名空间。但事后检查：

```bash
grep -c ubuntu-resolute /proc/mounts    # 789
```

**789 个挂载点泄漏到了父命名空间。**

## 根因：挂载传播

`unshare -m` 只创建命名空间，**不改变挂载点的传播属性**。如果父命名空间里的 `/` 是 `shared`，那么子命名空间里发生的挂载会**反向传播**回父命名空间。

阻止它只需要一步：

```bash
mount --make-rprivate /
```

问题在于：**Android 自带的 toybox `mount` 根本没有实现传播标志**。

```bash
mount --make-rprivate /
# mount: bad /etc/fstab: No such file or directory
```

它把 `--make-rprivate` 当成了 fstab 文件去解析。这不是权限问题，是工具能力问题。

## 解决方案：KernelSU 自带的 busybox

```bash
/data/adb/ksu/bin/busybox mount --make-rprivate /
```

验证隔离是否真的生效（在子命名空间内执行）：

```bash
unshare -m sh -c '
  busybox mount --make-rprivate / || exit 10
  SH=$(busybox grep -c " shared:" /proc/self/mountinfo)
  [ "$SH" = "0" ] || exit 11
  echo isolation-ok
'
```

`shared` 计数归零，才算隔离成功；不成功就**一个挂载都不要做**。

## 事故的连带伤害

那次泄漏之后，系统出现了更严重的问题：

```bash
stat /dev/binderfs/binder
# No such file or directory
ls /dev/binderfs      # 空的
```

binderfs 里的设备节点消失了，导致**所有新进程**（包括 Termux、artd）启动时 abort：

```
Abort message: 'Binder driver ... Opening '/dev/binder' failed ... Terminating.'
```

已经在跑的 `system_server` 因为握着旧 fd 还活着，所以系统看起来「没死」，但任何新应用都起不来。

最终只能重启恢复——init 会重建 binderfs，同时清掉泄漏的挂载。**挂载泄漏本身不会删节点，它和 binderfs 的关系至今没有完全坐实**，但两者都指向同一个方向：不要在全局命名空间里乱动挂载。

## 本项目的防御措施

三道防线，缺一不可：

```bash
# 1) 前置：设传播为 private，并校验
busybox mount --make-rprivate / || exit 10
SH=$(busybox grep -c " shared:" /proc/self/mountinfo)
[ "$SH" = "0" ] || exit 11

# 2) 挂载全部在 unshare -m 内，失败立即退出（不做「失败也继续」）
mount -t proc proc "$D/proc" || exit 12
mount --bind /dev "$D/dev"      || exit 14

# 3) 后置：核对父命名空间挂载数没变
echo "parent_mounts_after=$(grep -c '' /proc/mounts)"
```

退出码约定：

| 退出码 | 含义 |
|---|---|
| 10 | 设置传播失败（未做任何挂载） |
| 11 | 隔离未生效（未做任何挂载） |
| 12–15 | 对应的具体挂载失败 |

## 清理

**不要手动 `umount`**。挂载活在会话的私有命名空间里，最后一个进程退出时内核自动销毁它们。手动卸载反而容易在错误的命名空间里操作。

停止脚本只负责杀进程，然后校验：

```bash
grep -cF "$CONTAINER" /proc/mounts   # 正常应为 0
```

## 一条经验

> 在 Android 上做挂载，先问三个问题：
> 1. 这个操作在命名空间里吗？
> 2. 传播属性是 private 吗？
> 3. 失败时会不会留下半截状态？

三个问题都答不上来，就别执行。

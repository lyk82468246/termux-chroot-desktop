#!/data/data/com.termux/files/usr/bin/bash
# termux-gui-stop.sh —— 从任意状态停止桌面、容器会话与 X 服务
#
# 用法: bash termux-gui-stop.sh [--force]
#
# 两个要点：
# 1. Termux 与 Termux:X11 共用同一 Android UID（通常 10234），
#    所以绝不能用 `am force-stop com.termux.x11`——AMS 会按 UID 杀进程，
#    把 Termux 本体一起带走。这里按进程名精确 kill。
# 2. 整个脚本只提权一次，其余全部以 root 直接执行，
#    避免嵌套 `su`（每次约 2-5 秒）。

set -uo pipefail

PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
DISPLAY_NUM=${DISPLAY_NUM:-:0}
BUSYBOX=${BUSYBOX:-/data/adb/ksu/bin/busybox}
CONTAINER=${CONTAINER:-}
FORCE=${FORCE:-0}
[[ ${1:-} == "--force" ]] && FORCE=1

die()  { printf '\033[31m[✗] %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m[✓] %s\033[0m\n' "$*"; }
warn() { printf '\033[33m[!] %s\033[0m\n' "$*"; }
info() { printf '[*] %s\n' "$*"; }

# ---------- 非 root：一次性提权重跑自己 ----------
if [[ $(id -u) -ne 0 ]]; then
  [[ -n $CONTAINER ]] || CONTAINER=$(ls -d "$HOME/.local/share/tmoe-linux/containers/chroot"/ubuntu-* 2>/dev/null | head -1)
  [[ -n ${CONTAINER:-} ]] || die "找不到容器目录，请用 CONTAINER=/path 指定"
  [[ -x $PREFIX/bin/bash ]] || die "缺少 Termux bash"

  SU="$(command -v su || echo /system/bin/su)"
  [[ -x $SU ]] || die "找不到 su"

  SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  [[ -r $SELF ]] || die "无法定位自身路径: $SELF"

  exec "$SU" -c "HOME='$HOME' PREFIX='$PREFIX' BUSYBOX='$BUSYBOX' CONTAINER='$CONTAINER' DISPLAY_NUM='$DISPLAY_NUM' FORCE='$FORCE' '$PREFIX/bin/bash' '$SELF'"
fi

# ---------- 以下全部以 root 执行 ----------
[[ -n ${CONTAINER:-} ]] || CONTAINER=$(ls -d "$HOME/.local/share/tmoe-linux/containers/chroot"/ubuntu-* 2>/dev/null | head -1)
[[ -n ${CONTAINER:-} ]] || die "找不到容器目录，请用 CONTAINER=/path 指定"
[[ -x $BUSYBOX ]] || die "找不到 busybox: $BUSYBOX"

STATE="${TMPDIR:-/tmp}/termux-gui"
PIDF="$PREFIX/tmp/termux-gui/session.pid"

# 容器内进程（root 视角，不受 hidepid 限制）
# 用一次 ls 解析全部 /proc/*/root，避免对每个进程 fork readlink（700 进程≈20s）
deep_pids() {
  ls -l /proc/[0-9]*/root 2>/dev/null \
    | grep -F -- "-> $CONTAINER" \
    | sed -n 's|.*/proc/\([0-9]*\)/root.*|\1|p'
}

# X 服务进程：busybox pgrep 一次搞定，避免逐进程扫 cmdline
# X 进程检测：走 /proc 的 cmdline + comm=main，不依赖 ps 的具体实现
x11_pids() {
  local f p
  for f in $(grep -la "termux-x11 com" /proc/[0-9]*/cmdline 2>/dev/null); do
    p=${f#/proc/}; p=${p%/cmdline}
    [ "$(cat /proc/$p/comm 2>/dev/null)" = "main" ] && echo "$p"
  done
}

# 关闭 Termux:X11 应用本体（按进程名，绝不 force-stop）
close_x11_app() {
  local p
  p=$(pidof com.termux.x11 2>/dev/null || true)
  if [ -z "$p" ]; then
    # pidof 对 Android 应用进程不一定可靠，按进程名扫 ps 兜底
    p=$(ps -A -o PID,NAME 2>/dev/null | grep -w "com.termux.x11" | grep -v grep | awk '{print $1}' | head -1)
  fi
  [ -n "$p" ] || return 0
  kill $p 2>/dev/null || kill -9 $p 2>/dev/null
}

x11_app_running() {
  pidof com.termux.x11 >/dev/null 2>&1 && return 0
  ps -A -o PID,NAME 2>/dev/null | grep -qw "com.termux.x11" && return 0
  return 1
}

DEEP=$(deep_pids | tr '\n' ' ')
XIDS=$(x11_pids | tr '\n' ' ')

if [ -z "${DEEP// /}" ] && [ -z "${XIDS// /}" ]; then
  close_x11_app
  ok "已处于停止状态"
  rm -f "$PIDF"
  exit 0
fi

# ---------- 1. 终止容器会话 ----------
if [ -n "${DEEP// /}" ]; then
  info "容器内进程数: $(echo "$DEEP" | wc -w)"
  $BUSYBOX kill -TERM $DEEP 2>/dev/null
  sleep 1.5
  REMAIN=$(deep_pids | tr '\n' ' ')
  if [ -n "${REMAIN// /}" ]; then
    warn "强制终止残留: $(echo "$REMAIN" | wc -w) 个"
    $BUSYBOX kill -KILL $REMAIN 2>/dev/null
    sleep 0.8
  fi
fi

# ---------- 2. 停止 X 服务 ----------
XIDS=$(x11_pids | tr '\n' ' ')
if [ -n "${XIDS// /}" ]; then
  info "停止 X 服务"
  kill -TERM $XIDS 2>/dev/null
  sleep 1
  XIDS=$(x11_pids | tr '\n' ' ')
  [ -n "${XIDS// /}" ] && kill -KILL $XIDS 2>/dev/null
fi
# 等 X 真正退出再清 socket：X 退出时会自己 unlink socket + rmdir 目录，
# 提前删除会让下次启动的竞态更难判断
for _ in $(seq 1 20); do
  [ -z "$(x11_pids)" ] && break
  sleep 0.25
done
rm -f "$PREFIX/tmp/.X${DISPLAY_NUM#:}-lock" "$PREFIX/tmp/.X11-unix/X${DISPLAY_NUM#:}"
mkdir -p "$PREFIX/tmp/.X11-unix" 2>/dev/null
chmod 1777 "$PREFIX/tmp/.X11-unix" 2>/dev/null || true

# ---------- 3. 关闭 Termux:X11 应用（保留 Termux）----------
if x11_app_running; then
  info "关闭 Termux:X11 应用（保留 Termux）"
  close_x11_app
fi

# ---------- 4. 校验 ----------
rm -f "$PIDF"

LEFT=$(deep_pids | tr '\n' ' ')
if [ -n "${LEFT// /}" ]; then
  warn "仍有残留进程: $(echo "$LEFT" | wc -w) 个（可加 --force 重试）"
  if [ "$FORCE" = 1 ]; then
    $BUSYBOX kill -KILL $LEFT 2>/dev/null
    sleep 0.5
    LEFT=$(deep_pids | tr '\n' ' ')
  fi
fi
[ -z "${LEFT// /}" ] && ok "容器会话已全部退出"

MOUNTS=$(grep -cF "$CONTAINER" /proc/mounts 2>/dev/null || true)
MOUNTS=${MOUNTS:-0}
if [ "$MOUNTS" -gt 0 ]; then
  warn "检测到 $MOUNTS 个全局残留挂载（正常应为 0）"
else
  ok "无全局残留挂载"
fi

ok "已停止"

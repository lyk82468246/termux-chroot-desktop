#!/data/data/com.termux/files/usr/bin/bash
# termux-gui-stop.sh —— 从任意状态停止桌面、容器会话与 X 服务
#
# 用法: bash termux-gui-stop.sh [--force]

set -uo pipefail

PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
DISPLAY_NUM=${DISPLAY_NUM:-:0}
BUSYBOX=${BUSYBOX:-/data/adb/ksu/bin/busybox}
CONTAINER=${CONTAINER:-}
FORCE=0
[[ ${1:-} == "--force" ]] && FORCE=1

STATE="$PREFIX/tmp/termux-gui"
PIDF="$STATE/session.pid"
SCAN="$STATE/scan-chroot.sh"

die()  { printf '\033[31m[✗] %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m[✓] %s\033[0m\n' "$*"; }
warn() { printf '\033[33m[!] %s\033[0m\n' "$*"; }
info() { printf '[*] %s\n' "$*"; }

[[ -n $CONTAINER ]] || CONTAINER=$(ls -d "$HOME/.local/share/tmoe-linux/containers/chroot"/ubuntu-* 2>/dev/null | head -1)
[[ -n ${CONTAINER:-} ]] || die "找不到容器目录，请用 CONTAINER=/path 指定"

SU="$(command -v su || echo /system/bin/su)"
[[ -x $SU ]] || die "找不到 su"
"$SU" -c "test -x '$BUSYBOX'" 2>/dev/null || die "root 侧找不到可执行的 busybox: $BUSYBOX"

mkdir -p "$STATE"
cat > "$SCAN" <<'EOF'
#!/system/bin/sh
C=$1
for l in /proc/[0-9]*/root; do
  [ -L "$l" ] || continue
  t=$(readlink "$l" 2>/dev/null) || continue
  case "$t" in "$C"|"$C "*) ;; *) continue ;; esac
  p=${l#/proc/}; echo "${p%/root}"
done
EOF

# 容器内全部进程（root 视角，绕过 hidepid）
deep_pids() { "$SU" -c "sh '$SCAN' '$CONTAINER'" 2>/dev/null | sort -un; }

# 当前用户的 X 服务进程
x11_pids() {
  local f
  for f in /proc/[0-9]*/cmdline; do
    [[ -r $f ]] || continue
    tr '\0' ' ' < "$f" 2>/dev/null | grep -qF "termux-x11" && { f=${f#/proc/}; echo "${f%/cmdline}"; }
  done
}

DEEP=$(deep_pids | tr '\n' ' ')
XIDS=$(x11_pids | tr '\n' ' ')

if [[ -z ${DEEP// /} && -z ${XIDS// /} ]]; then
  # 即使服务已停，也要把 Termux:X11 应用收掉（它可能停在 "Not connected"）
  "$SU" -c "am force-stop com.termux.x11" 2>/dev/null
  ok "已处于停止状态"
  rm -f "$PIDF"
  exit 0
fi

# ---------- 1. 终止容器会话 ----------
if [[ -n ${DEEP// /} ]]; then
  info "容器内进程数: $(echo $DEEP | wc -w)"
  "$SU" -c "$BUSYBOX kill -TERM $DEEP" 2>/dev/null
  for _ in $(seq 1 20); do
    [[ -z $(deep_pids) ]] && break
    sleep 0.5
  done
  REMAIN=$(deep_pids | tr '\n' ' ')
  if [[ -n ${REMAIN// /} ]]; then
    warn "强制终止残留: $(echo $REMAIN | wc -w) 个"
    "$SU" -c "$BUSYBOX kill -KILL $REMAIN" 2>/dev/null
    sleep 1
  fi
fi

# ---------- 2. 停止 X 服务 ----------
XIDS=$(x11_pids | tr '\n' ' ')
if [[ -n ${XIDS// /} ]]; then
  info "停止 X 服务"
  kill -TERM $XIDS 2>/dev/null
  for _ in $(seq 1 10); do
    [[ -z $(x11_pids) ]] && break
    sleep 0.3
  done
  XIDS=$(x11_pids | tr '\n' ' ')
  [[ -n ${XIDS// /} ]] && kill -KILL $XIDS 2>/dev/null
  rm -f "$PREFIX/tmp/.X${DISPLAY_NUM#:}-lock" "$PREFIX/tmp/.X11-unix/X${DISPLAY_NUM#:}"
fi

# 关闭 Termux:X11 应用，避免停留 "Not connected" 界面
info "关闭 Termux:X11 应用"
"$SU" -c "am force-stop com.termux.x11" 2>/dev/null \
  || warn "无法关闭 Termux:X11 应用，请手动退出"

# ---------- 3. 收尾校验 ----------
rm -f "$PIDF"

LEFT=$(deep_pids | tr '\n' ' ')
if [[ -n ${LEFT// /} ]]; then
  warn "仍有残留进程: $(echo $LEFT | wc -w) 个（可加 --force 重试）"
  [[ $FORCE == 1 ]] && "$SU" -c "$BUSYBOX pkill -KILL -f '$CONTAINER'" 2>/dev/null
else
  ok "容器会话已全部退出"
fi

MOUNTS=$(grep -cF "$CONTAINER" /proc/mounts 2>/dev/null || true)
MOUNTS=${MOUNTS:-0}
if [[ $MOUNTS -gt 0 ]]; then
  warn "检测到 $MOUNTS 个全局残留挂载（正常应为 0）"
else
  ok "无全局残留挂载"
fi

ok "已停止"

#!/data/data/com.termux/files/usr/bin/bash
# termux-gui-start.sh —— 从任意状态启动到「桌面正常运行」，脚本立即返回
# 会话完全脱离当前终端（setsid），关掉 Termux 应用也不会中断容器。
#
# 用法: bash termux-gui-start.sh
# 环境变量: CONTAINER / DISPLAY_NUM / DPI / DESKTOP_CMD / COMPOSITOR / BUSYBOX
#   COMPOSITOR=none  （默认）无合成器：无阴影/透明，最省电
#   COMPOSITOR=picom 使用 picom xrender 后端：有阴影/透明，合成走 CPU

set -uo pipefail

PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
export TMPDIR="$PREFIX/tmp"
export PATH="$PREFIX/bin:$PATH"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-$PREFIX/lib}"
DISPLAY_NUM=${DISPLAY_NUM:-:0}
DPI=${DPI:-160}
DESKTOP_CMD=${DESKTOP_CMD:-"dbus-run-session -- startxfce4"}
# 合成器: none（默认，无阴影、最省）/ picom（xrender 后端，有阴影，CPU 合成）
COMPOSITOR=${COMPOSITOR:-none}
BUSYBOX=${BUSYBOX:-/data/adb/ksu/bin/busybox}
CONTAINER=${CONTAINER:-}

STATE="$PREFIX/tmp/termux-gui"
PIDF="$STATE/session.pid"
LOG="$STATE/session.log"
XLOG="$STATE/x11.log"
HELPER="$STATE/root-helper.sh"
PICOM_HELPER="$STATE/picom-helper.sh"
PICOM_LOG="$STATE/picom.log"
PICOM_SCAN="$STATE/scan-picom.sh"

die()  { printf '\033[31m[✗] %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m[✓] %s\033[0m\n' "$*"; }
warn() { printf '\033[33m[!] %s\033[0m\n' "$*"; }
info() { printf '[*] %s\n' "$*"; }

# ---------- 定位容器 ----------
if [[ -z $CONTAINER ]]; then
  CONTAINER=$(ls -d "$HOME/.local/share/tmoe-linux/containers/chroot"/ubuntu-* 2>/dev/null | head -1)
fi
[[ -n ${CONTAINER:-} && -d $CONTAINER ]] || die "找不到 chroot 容器，请用 CONTAINER=/path/to/rootfs 指定"

# ---------- 运行状态探测（经 su 扫描 /proc/*/root，绕过 hidepid）----------
SU_CMD="$(command -v su || echo /system/bin/su)"
mkdir -p "$STATE"
SCAN="$STATE/scan-chroot.sh"
cat > "$SCAN" <<'EOF'
#!/system/bin/sh
C=$1
for l in /proc/[0-9]*/root; do
  [ -L "$l" ] || continue
  t=$(readlink "$l" 2>/dev/null) || continue
  case "$t" in "$C"|"$C "*) ;; *) continue ;; esac
  p=${l#/proc/}; p=${p%/root}
  cmd=$(tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null)
  case "$cmd" in
    *startxfce4*|*dbus-run-session*|*xfce4-session*|*startlxqt*|*openbox*) echo "$p" ;;
  esac
done
EOF

session_pids() { "$SU_CMD" -c "sh '$SCAN' '$CONTAINER'" 2>/dev/null | sort -un; }

# ---------- 合成器（可选 picom，xrender/CPU）----------
cat > "$PICOM_SCAN" <<'EOF'
#!/system/bin/sh
C=$1
for l in /proc/[0-9]*/root; do
  [ -L "$l" ] || continue
  t=$(readlink "$l" 2>/dev/null) || continue
  case "$t" in "$C"|"$C "*) ;; *) continue ;; esac
  p=${l#/proc/}; p=${p%/root}
  tr '\0' ' ' < /proc/$p/cmdline 2>/dev/null | grep -q "picom --backend" && echo "$p"
done
EOF

picom_running() { "$SU_CMD" -c "sh '$PICOM_SCAN' '$CONTAINER'" 2>/dev/null; }


# picom 启动辅助脚本（值在此处固化）
cat > "$PICOM_HELPER" <<PICOMEOF
#!/system/bin/sh
BB=$BUSYBOX
D=$CONTAINER
P=$PREFIX
"\$BB" unshare -m sh -c '
  BB="$BUSYBOX"
  D="$CONTAINER"
  P="$PREFIX"
  "\$BB" mount --make-rprivate / || exit 10
  "\$BB" mount -t proc proc "\$D/proc" || exit 12
  "\$BB" mount --bind /dev "\$D/dev" || exit 14
  "\$BB" mount --bind "\$P/tmp/.X11-unix" "\$D/tmp/.X11-unix" || exit 15
  exec chroot "\$D" /usr/bin/env -i DISPLAY=:0 MESA_LOADER_DRIVER_OVERRIDE=kgsl \\
    PATH=/usr/bin:/bin HOME=/root /usr/bin/picom --backend xrender --vsync
'
PICOMEOF
chmod 644 "$PICOM_HELPER"
start_compositor() {
  [[ ${COMPOSITOR:-none} == picom ]] || return 0
  if [[ -n $(picom_running) ]]; then ok "合成器 picom 已在运行"; return 0; fi
  info "启动合成器 picom (xrender, CPU 合成) ..."
  : > "$PICOM_LOG"
  setsid nohup "$SU_CMD" -c "sh '$PICOM_HELPER'" >>"$PICOM_LOG" 2>&1 </dev/null &
  sleep 4
  if [[ -n $(picom_running) ]]; then
    ok "合成器已启动（窗口带阴影）"
  else
    warn "合成器启动失败，见 $PICOM_LOG"
  fi
}

x11_pids() {
  local d pid c
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    tr '\0' ' ' < "$d/cmdline" 2>/dev/null | grep -qF "termux-x11" && { echo "$pid"; continue; }
    c=$(cat "$d/comm" 2>/dev/null) || continue
    case "$c" in termux-x11*) echo "$pid" ;; esac
  done
}

XSOCK="$PREFIX/tmp/.X11-unix/X${DISPLAY_NUM#:}"

mapfile -t RUNNING < <(session_pids)
if (( ${#RUNNING[@]} > 0 )); then
  ok "桌面已在运行（容器内 ${#RUNNING[@]} 个进程）"
  info "日志: $LOG"
  # 顺手确保 X 应用在前台
  if /system/bin/am start -n com.termux.x11/.MainActivity >/dev/null 2>&1 \
     || "$SU_CMD" -c "/system/bin/am start -n com.termux.x11/.MainActivity" >/dev/null 2>&1; then
    ok "Termux:X11 应用已切到前台"
  else
    warn "无法拉起 Termux:X11 应用"
  fi
  start_compositor
  exit 0
fi

# ---------- 读取 TMOE 配置（挂载点 / 用户）----------
LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/termux-gui-lib.sh"
if [[ -r $LIB ]]; then
  # shellcheck disable=SC1090
  source "$LIB"
  tmoe_resolve
  ok "TMOE 配置: 桌面用户=$CHROOT_USER  额外挂载=$(tmoe_summary)"
  # 默认跟随 TMOE 的主用户；DESKTOP_AS_ROOT=1 可强制用 root
  if [[ ${DESKTOP_AS_ROOT:-0} == 1 ]]; then
    USER_HOME=/root
    USER_WRAP=""
    USER_UID=0
    USER_GID=0
    CHROOT_USER=root
  fi
else
  warn "未找到 $LIB，跳过 TMOE 配置解析"
fi

# ---------- 前置检查 ----------
SU="$(command -v su || echo /system/bin/su)"
[[ -x $SU ]] || die "找不到 su（需要 KernelSU/Magisk）"
[[ -x $PREFIX/bin/termux-x11 ]] || die "缺少 termux-x11：pkg install x11-repo && pkg install termux-x11-nightly"
"$SU" -c "test -x '$BUSYBOX'" 2>/dev/null || die "root 侧找不到可执行的 busybox: $BUSYBOX"
DESK_BIN=${DESKTOP_CMD##* }
[[ -x "$CONTAINER/usr/bin/$DESK_BIN" || -x "$CONTAINER/usr/sbin/$DESK_BIN" ]] \
  || die "容器内找不到 $DESK_BIN，桌面未安装（apt install xfce4 dbus-x11 fonts-noto-cjk）"
[[ -f "$CONTAINER/usr/lib/aarch64-linux-gnu/dri/msm_dri.so" ]] \
  || warn "未找到 msm_dri.so，KGSL 版 Mesa 可能未安装"

if [[ ${COMPOSITOR:-none} == picom ]]; then
  [[ -x "$CONTAINER/usr/bin/picom" ]] || die "COMPOSITOR=picom 但容器内没有 picom（apt install picom）"
  ok "合成器: picom (xrender)"
else
  ok "合成器: 关闭"
fi

mkdir -p "$STATE"

# ---------- X 服务 ----------
# 只认「socket 存在 + 进程活着」，避免被上次 kill 留下的僵尸 socket 骗到
if [[ -S $XSOCK && -n $(x11_pids) ]]; then
  ok "X 服务已在运行"
else
  [[ -S $XSOCK ]] && warn "发现残留 socket（服务已死），清理后重启"
  rm -f "$XSOCK" "$PREFIX/tmp/.X${DISPLAY_NUM#:}-lock"
  : > "$XLOG"
  X_OK=0
  for attempt in 1 2 3; do
    info "启动 X 服务 (第 $attempt 次尝试) ..."
    nohup "$PREFIX/bin/termux-x11" "$DISPLAY_NUM" -ac -dpi "$DPI" >>"$XLOG" 2>&1 </dev/null &
    for _ in $(seq 1 40); do
      [[ -S $XSOCK ]] && break
      sleep 0.3
    done
    sleep 3   # 等 X 完成初始化，观察是否崩溃
    if [[ -S $XSOCK ]] && [[ -n $(x11_pids) ]]; then X_OK=1; break; fi
    warn "第 $attempt 次失败：$(tail -3 "$XLOG" | tr '\n' ' ')"
    pkill -f "termux-x11 $DISPLAY_NUM" 2>/dev/null
    rm -f "$XSOCK" "$PREFIX/tmp/.X${DISPLAY_NUM#:}-lock"
    sleep 1
  done
  [[ $X_OK == 1 ]] || die "X 服务连续 3 次启动失败，见 $XLOG"
  ok "X 服务就绪"
fi

if /system/bin/am start -n com.termux.x11/.MainActivity >/dev/null 2>&1 \
   || "$SU_CMD" -c "/system/bin/am start -n com.termux.x11/.MainActivity" >/dev/null 2>&1; then
  ok "已拉起 Termux:X11 应用"
else
  warn "无法拉起 Termux:X11 应用，请手动打开"
fi

# ---------- 生成 root 侧脚本 ----------
cat > "$HELPER" <<'ROOTEOF'
#!/system/bin/sh
D=$1; DPY=$2; CMD=$3; P=$4; BB=$5; UHOME=$6; UW=$7; UUID=$8; UGID=$9; UNAME=${10}; USHELL=${11}; ULOGIN=${12}
[ -d "$D" ] || { echo "容器不存在: $D"; exit 2; }
mkdir -p "$D/proc" "$D/sys" "$D/dev" "$D/tmp/.X11-unix" 2>/dev/null
export D DPY CMD P BB UHOME UW UUID UGID UNAME USHELL ULOGIN
EXTRA="$P/tmp/termux-gui/extra-mounts.sh"
echo "parent_mounts_before=$(grep -c '' /proc/mounts)"
echo "desktop_user=$UNAME home=$UHOME"
"$BB" unshare -m sh -c '
  "$BB" mount --make-rprivate / || { echo "propagation failed"; exit 10; }
  SH=$("$BB" grep -c " shared:" /proc/self/mountinfo)
  [ "$SH" = "0" ] || { echo "isolation failed: shared=$SH"; exit 11; }
  "$BB" mount -t proc proc "$D/proc"        || exit 12
  "$BB" mount -t sysfs sysfs "$D/sys"       || exit 13
  "$BB" mount --bind /dev "$D/dev"          || exit 14
  "$BB" mount --bind /dev/pts "$D/dev/pts" 2>/dev/null || true
  "$BB" mount --bind "$P/tmp/.X11-unix" "$D/tmp/.X11-unix" || exit 15
  [ -r "$EXTRA" ] && . "$EXTRA"

  RUN="/tmp/runtime-$UNAME"
  chroot "$D" /bin/mkdir -p "$RUN" || exit 16
  chroot "$D" /bin/chmod 700 "$RUN" || exit 17
  chroot "$D" /bin/chown "$UUID:$UGID" "$RUN" 2>/dev/null || true

  # 把 root 的 xfwm4 配置复制给桌面用户，并强制关闭合成（Termux:X11 白屏问题）
  RCFG=/root/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml
  UCFG="$UHOME/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml"
  if [ -f "$D$RCFG" ] && [ ! -f "$D$UCFG" ]; then
    chroot "$D" /bin/mkdir -p "$UHOME/.config/xfce4/xfconf/xfce-perchannel-xml" 2>/dev/null
    chroot "$D" /bin/cp "$RCFG" "$UCFG" 2>/dev/null
    chroot "$D" /bin/chown -R "$UUID:$UGID" "$UHOME/.config" 2>/dev/null
  fi
  if [ -f "$D$UCFG" ]; then
    chroot "$D" /bin/sed -i "s/name=\"use_compositing\" type=\"bool\" value=\"true\"/name=\"use_compositing\" type=\"bool\" value=\"false\"/" "$UCFG" 2>/dev/null || true
  fi

  exec chroot "$D" /usr/bin/env -i \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME="$UHOME" USER="$UNAME" LOGNAME="$UNAME" SHELL="$USHELL" DISPLAY="$DPY" \
    MESA_LOADER_DRIVER_OVERRIDE=kgsl \
    XDG_RUNTIME_DIR="$RUN" \
    $UW "$USHELL" $ULOGIN -c "$CMD"
'
rc=$?
echo "parent_mounts_after=$(grep -c '' /proc/mounts)"
exit $rc
ROOTEOF
chmod 644 "$HELPER"

# ---------- 后台启动会话（setsid: 脱离终端与进程组）----------
info "启动容器桌面 (后台) ..."
: > "$LOG"
if declare -f tmoe_write_mounts >/dev/null; then
  tmoe_write_mounts "$STATE/extra-mounts.sh" "$CONTAINER" "$BUSYBOX"
fi
setsid bash -c '
  echo $$ > "$1"
  exec "$2" -c "sh \"$3\" \"$4\" \"$5\" \"$6\" \"$7\" \"$8\" \"$9\" \"${10}\" \"${11}\" \"${12}\" \"${13}\" \"${14}\" \"${15}\""
' _ "$PIDF" "$SU" \
    "$HELPER" "$CONTAINER" "$DISPLAY_NUM" "$DESKTOP_CMD" "$PREFIX" "$BUSYBOX" \
    "${USER_HOME:-/root}" "${USER_WRAP:-}" "${USER_UID:-0}" "${USER_GID:-0}" "${CHROOT_USER:-root}" \
    "${USER_SHELL:-/bin/sh}" "${USER_LOGIN_ARG:--l}" \
  >>"$LOG" 2>&1 </dev/null &

# 等桌面进程出现（最多 30 秒）
RUNNING=()
for _ in $(seq 1 15); do
  mapfile -t RUNNING < <(session_pids)
  (( ${#RUNNING[@]} > 0 )) && break
  sleep 2
done

if (( ${#RUNNING[@]} > 0 )); then
  ok "桌面已启动 (共 ${#RUNNING[@]} 个容器内进程)"
  start_compositor
  info "日志: $LOG"
  info "停止: bash termux-gui-stop.sh"
  exit 0
else
  warn "30 秒内未检测到容器进程，最近日志："
  tail -20 "$LOG" 2>/dev/null
  warn "如首次使用，请先在 Termux 里执行: su -c id  完成 root 授权"
  exit 1
fi

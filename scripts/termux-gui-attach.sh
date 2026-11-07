#!/data/data/com.termux/files/usr/bin/bash
# termux-gui-attach.sh —— 从 Termux 进入 Ubuntu 容器终端
#
# 用法:
#   bash termux-gui-attach.sh                 # 交互式登录 shell（exit / Ctrl-D 返回）
#   bash termux-gui-attach.sh uname -a        # 执行一条命令后退出
#   bash termux-gui-attach.sh -- bash -l      # 显式指定
#
# 可覆盖: CONTAINER / DISPLAY_NUM / BUSYBOX

set -uo pipefail

PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
export TMPDIR="$PREFIX/tmp"
export PATH="$PREFIX/bin:$PATH"
DISPLAY_NUM=${DISPLAY_NUM:-:0}
BUSYBOX=${BUSYBOX:-/data/adb/ksu/bin/busybox}
CONTAINER=${CONTAINER:-}

STATE="$PREFIX/tmp/termux-gui"
HELPER="$STATE/attach-helper.sh"
CMDFILE="$STATE/attach-cmd.txt"

die()  { printf '\033[31m[✗] %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m[✓] %s\033[0m\n' "$*"; }
info() { printf '[*] %s\n' "$*"; }

[[ ${1:-} == "--" ]] && shift
CMDLINE=""
(( $# > 0 )) && CMDLINE="$*"

# ---------- 定位容器 ----------
if [[ -z $CONTAINER ]]; then
  CONTAINER=$(ls -d "$HOME/.local/share/tmoe-linux/containers/chroot"/ubuntu-* 2>/dev/null | head -1)
fi
[[ -n ${CONTAINER:-} && -d $CONTAINER ]] || die "找不到 chroot 容器，请用 CONTAINER=/path/to/rootfs 指定"

SU="$(command -v su || echo /system/bin/su)"
[[ -x $SU ]] || die "找不到 su（需要 KernelSU/Magisk）"
"$SU" -c "test -x '$BUSYBOX'" 2>/dev/null || die "root 侧找不到 busybox: $BUSYBOX"

# ---------- 读取 TMOE 配置 ----------
LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/termux-gui-lib.sh"
if [[ -r $LIB ]]; then
  # shellcheck disable=SC1090
  source "$LIB"
  tmoe_resolve
  info "TMOE: 用户=$CHROOT_USER  挂载=$(tmoe_summary)"
  tmoe_write_mounts "$STATE/extra-mounts.sh" "$CONTAINER" "$BUSYBOX"
else
  warn "未找到 $LIB，跳过 TMOE 配置解析"
  USER_HOME=/root
  USER_WRAP=""
  USER_SHELL=/bin/sh
  USER_LOGIN_ARG=-l
  LOCALE_RESOLVED=${LOCALE:-en_US.UTF-8}
fi

mkdir -p "$STATE"
if [[ -n $CMDLINE ]]; then
  printf '%s\n' "$CMDLINE" > "$CMDFILE"
else
  rm -f "$CMDFILE"
fi



if [[ -S "$PREFIX/tmp/.X11-unix/X${DISPLAY_NUM#:}" ]]; then
  info "桌面会话在运行，DISPLAY=$DISPLAY_NUM（图形程序可用）"
else
  info "桌面未运行（终端照常可用，图形程序会失败）"
fi

# ---------- 生成 root 侧辅助脚本 ----------
INNER="$STATE/attach-inner.sh"

# 内层：挂载 + chroot + 进 shell（全部双引号，避免嵌套引号被破坏）
cat > "$INNER" <<INNEREOF
#!/bin/sh
$BUSYBOX mount --make-rprivate / || exit 10
SH=\$($BUSYBOX grep -c " shared:" /proc/self/mountinfo)
[ "\$SH" = "0" ] || { echo "isolation failed: shared=\$SH"; exit 11; }
$BUSYBOX mount -t proc proc "$CONTAINER/proc" || exit 12
$BUSYBOX mount -t sysfs sysfs "$CONTAINER/sys" 2>/dev/null || true
$BUSYBOX mount --bind /dev "$CONTAINER/dev" || exit 13
$BUSYBOX mount --bind /dev/pts "$CONTAINER/dev/pts" 2>/dev/null || true
mkdir -p "$CONTAINER/tmp/.X11-unix" "$CONTAINER/tmp/runtime-$CHROOT_USER" 2>/dev/null
chmod 700 "$CONTAINER/tmp/runtime-$CHROOT_USER" 2>/dev/null

# 同 start：/data 为 nosuid，sudo 需要 tmpfs 上的 setuid 副本
if [ -f "$CONTAINER/usr/lib/cargo/bin/sudo" ]; then
  mkdir -p "$CONTAINER/run/sudobin" 2>/dev/null
  if $BUSYBOX mount -t tmpfs -o mode=0755,uid=0,gid=0 tmpfs "$CONTAINER/run/sudobin" 2>/dev/null; then
    cp "$CONTAINER/usr/lib/cargo/bin/sudo" "$CONTAINER/run/sudobin/sudo" 2>/dev/null
    chown 0:0 "$CONTAINER/run/sudobin/sudo" 2>/dev/null
    chmod 4755 "$CONTAINER/run/sudobin/sudo" 2>/dev/null
    chroot "$CONTAINER" /bin/mkdir -p /usr/local/bin 2>/dev/null
    chroot "$CONTAINER" /bin/ln -sf /run/sudobin/sudo /usr/local/bin/sudo 2>/dev/null
  fi
fi
chown ${USER_UID:-0}:${USER_GID:-0} "$CONTAINER/tmp/runtime-$CHROOT_USER" 2>/dev/null
[ -d "$PREFIX/tmp/.X11-unix" ] && $BUSYBOX mount --bind "$PREFIX/tmp/.X11-unix" "$CONTAINER/tmp/.X11-unix" 2>/dev/null
[ -r "$STATE/extra-mounts.sh" ] && . "$STATE/extra-mounts.sh"
if [ -s "$CONTAINER/tmp/attach-cmd" ]; then
  exec chroot "$CONTAINER" /usr/bin/env -i \\
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \\
    HOME="$USER_HOME" TERM="\${TERM:-xterm-256color}" DISPLAY="$DISPLAY_NUM" \\
    LANG="$LOCALE_RESOLVED" LC_ALL="$LOCALE_RESOLVED" \\
    MESA_LOADER_DRIVER_OVERRIDE=kgsl XDG_RUNTIME_DIR=/tmp/runtime-$CHROOT_USER SHELL="$USER_SHELL" USER="$CHROOT_USER" LOGNAME="$CHROOT_USER" \\
    $USER_WRAP $USER_SHELL $USER_LOGIN_ARG -c "\$(cat "$CONTAINER/tmp/attach-cmd")"
fi
exec chroot "$CONTAINER" /usr/bin/env -i \\
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \\
  HOME="$USER_HOME" TERM="\${TERM:-xterm-256color}" DISPLAY="$DISPLAY_NUM" \\
  LANG="$LOCALE_RESOLVED" LC_ALL="$LOCALE_RESOLVED" \\
  MESA_LOADER_DRIVER_OVERRIDE=kgsl XDG_RUNTIME_DIR=/tmp/runtime-$CHROOT_USER SHELL="$USER_SHELL" USER="$CHROOT_USER" LOGNAME="$CHROOT_USER" \\
  $USER_WRAP $USER_SHELL $USER_LOGIN_ARG
INNEREOF
chmod 644 "$INNER"

# 外层：拷贝待执行命令 + 在私有挂载命名空间里跑内层脚本
cat > "$HELPER" <<EOF
#!/system/bin/sh
if [ -s "$CMDFILE" ]; then
  cp "$CMDFILE" "$CONTAINER/tmp/attach-cmd"
else
  rm -f "$CONTAINER/tmp/attach-cmd"
fi
exec $BUSYBOX unshare -m /system/bin/sh "$INNER"
EOF
chmod 644 "$HELPER"

# ---------- 进入 ----------
if [[ -z $CMDLINE ]]; then
  ok "进入容器（exit 或 Ctrl-D 返回 Termux）"
fi

"$SU" -c "sh '$HELPER'"
RC=$?

[[ -n $CMDLINE ]] && exit $RC

case $RC in
  0)  ok "已退出容器" ;;
  10) die "设置挂载传播失败（未做任何挂载）" ;;
  11) die "命名空间隔离未生效（未做任何挂载）" ;;
  12|13) die "挂载失败，退出码 $RC" ;;
  *)  printf '\033[33m[!] 容器内命令退出码 %s\033[0m\n' "$RC" ;;
esac

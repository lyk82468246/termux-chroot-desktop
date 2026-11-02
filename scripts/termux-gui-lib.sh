#!/data/data/com.termux/files/usr/bin/bash
# termux-gui-lib.sh —— 解析 TMOE 的容器配置（挂载点、用户、环境）
# 由 termux-gui-start.sh / termux-gui-attach.sh source
#
# 解析来源（全部只读，不修改 TMOE 的文件）:
#   ~/.config/tmoe-linux/rootful/mount_sd.conf
#   ~/.config/tmoe-linux/rootful/mount_termux.conf
#   $CONTAINER/usr/local/etc/tmoe-linux/container/tmoe-linux-container  (CHROOT_USER)
#   $CONTAINER/usr/local/etc/tmoe-linux/wm_size.txt

# 读取 KEY=value 形式的配置（去掉引号与行尾注释）
tmoe_get() {
  local file=$1 key=$2
  [[ -r $file ]] || return 1
  sed -n "s/^[[:space:]]*${key}=//p" "$file" 2>/dev/null \
    | tail -1 | sed 's/[[:space:]]#.*$//' | tr -d '"' | tr -d "'"
}

# 解析结果写入全局变量；调用前需设置 CONTAINER
tmoe_resolve() {
  local confdir="$HOME/.config/tmoe-linux"
  local launcher="$CONTAINER/usr/local/etc/tmoe-linux/container/tmoe-linux-container"
  local envfile="$CONTAINER/usr/local/etc/tmoe-linux/environment/container.env"
  local wmsize="$CONTAINER/usr/local/etc/tmoe-linux/wm_size.txt"

  # ---- 挂载：SD 卡 / Termux home ----
  MOUNT_SD=$(tmoe_get "$confdir/rootful/mount_sd.conf" MOUNT_SD)
  MOUNT_SD=${MOUNT_SD:-false}
  SD_SRC=$(tmoe_get "$confdir/rootful/mount_sd.conf" SD_DIR_0)
  SD_SRC=${SD_SRC:-/data/media/0/Download}

  MOUNT_TERMUX=$(tmoe_get "$confdir/rootful/mount_termux.conf" MOUNT_TERMUX)
  MOUNT_TERMUX=${MOUNT_TERMUX:-false}
  TERMUX_SRC=$(tmoe_get "$confdir/rootful/mount_termux.conf" TERMUX_DIR)
  TERMUX_SRC=${TERMUX_SRC:-$HOME}

  # ---- 用户 ----
  CHROOT_USER=$(tmoe_get "$launcher" CHROOT_USER)
  CHROOT_USER=${CHROOT_USER:-root}

  USER_UID=""
  USER_GID=""
  USER_HOME="/root"
  if [[ $CHROOT_USER != root && -r "$CONTAINER/etc/passwd" ]]; then
    local line
    line=$(awk -F: -v u="$CHROOT_USER" '$1==u {print $3":"$4":"$6}' "$CONTAINER/etc/passwd" 2>/dev/null | head -1)
    if [[ -n $line ]]; then
      USER_UID=${line%%:*}
      local rest=${line#*:}
      USER_GID=${rest%%:*}
      USER_HOME=${rest#*:}
      [[ -n $USER_HOME ]] || USER_HOME="/home/$CHROOT_USER"
    fi
  fi

  # 用户切换命令（root 时为空）
  USER_WRAP=""
  if [[ -n $USER_UID && -n $USER_GID && $CHROOT_USER != root ]]; then
    if [[ -x "$CONTAINER/usr/bin/setpriv" ]]; then
      USER_WRAP="/usr/bin/setpriv --reuid=$USER_UID --regid=$USER_GID --init-groups"
    fi
  fi

  # ---- 登录 shell（严格按 TMOE 每容器脚本的规则）----
  # 1) Termux 侧 default_shell.conf 里的 TMOE_SHELL（若存在）
  # 2) 否则按 DEFAULT_LOGIN_SHELL_0..4 的顺序，取容器内第一个存在的
  # 3) 都没有则用容器 /etc/passwd 里该用户的 shell
  local shellconf cand="" c i
  shellconf=$(tmoe_get "$launcher" DEFAULT_SHELL_CONF)
  shellconf=${shellconf:-$HOME/.config/tmoe-linux/default_shell.conf}
  [[ -s $shellconf ]] && cand=$(tmoe_get "$shellconf" TMOE_SHELL)

  if [[ -z $cand ]]; then
    for i in \
      "$(tmoe_get "$launcher" DEFAULT_LOGIN_SHELL_0)" \
      "$(tmoe_get "$launcher" DEFAULT_LOGIN_SHELL_1)" \
      "$(tmoe_get "$launcher" DEFAULT_LOGIN_SHELL_2)" \
      "$(tmoe_get "$launcher" DEFAULT_LOGIN_SHELL_3)" \
      "$(tmoe_get "$launcher" DEFAULT_LOGIN_SHELL_4)"; do
      [[ -n $i ]] || continue
      case "$i" in */*) c=$i ;; *) c="/bin/$i" ;; esac
      if [[ -e "$CONTAINER$c" || -L "$CONTAINER$c" ]]; then cand=$c; break; fi
    done
  fi

  # TMOE：值不带斜杠时补 /bin/ 前缀
  if [[ -n $cand ]]; then
    case "$cand" in */*) ;; *) cand="/bin/$cand" ;; esac
  elif [[ -r "$CONTAINER/etc/passwd" ]]; then
    cand=$(awk -F: -v u="$CHROOT_USER" '$1==u {print $7}' "$CONTAINER/etc/passwd" 2>/dev/null | head -1)
  fi
  USER_SHELL=${cand:-/bin/sh}
  case "$USER_SHELL" in */nologin|*/false|"") USER_SHELL=/bin/sh ;; esac

  # TMOE 的登录参数（pwsh/nushell 不认 -l）
  USER_LOGIN_ARG=$(tmoe_get "$launcher" LOGIN_SHELL_ARG)
  USER_LOGIN_ARG=${USER_LOGIN_ARG:--l}
  case "$USER_SHELL" in
    */pwsh|*/nushell|*/nu) USER_LOGIN_ARG="" ;;
  esac

  # ---- 其他 ----
  WM_SIZE=$(cat "$wmsize" 2>/dev/null | tr -d '[:space:]')
  WM_SIZE=${WM_SIZE:-}
  ENV_FILE_IN_CONTAINER=""
  [[ -r $envfile ]] && ENV_FILE_IN_CONTAINER=/usr/local/etc/tmoe-linux/environment/container.env
}

# 生成额外挂载脚本（在私有命名空间内 source）
# 用法: tmoe_write_mounts <输出文件> <容器目录> <busybox>
tmoe_write_mounts() {
  local out=$1 D=$2 BB=$3
  {
    echo '#!/bin/sh'
    if [[ $MOUNT_SD == true && -n $SD_SRC ]]; then
      printf '[ -d "%s" ] && { mkdir -p "%s/media/sd" 2>/dev/null; %s mount --bind "%s" "%s/media/sd" 2>/dev/null; }\n' \
        "$SD_SRC" "$D" "$BB" "$SD_SRC" "$D"
    fi
    if [[ $MOUNT_TERMUX == true && -n $TERMUX_SRC ]]; then
      printf '[ -d "%s" ] && { mkdir -p "%s/media/termux" 2>/dev/null; %s mount --bind "%s" "%s/media/termux" 2>/dev/null; }\n' \
        "$TERMUX_SRC" "$D" "$BB" "$TERMUX_SRC" "$D"
    fi
    echo 'true'
  } > "$out"
  chmod 644 "$out"
}

# 人类可读的摘要
tmoe_summary() {
  local parts=()
  [[ $MOUNT_SD == true ]] && parts+=("SD:$SD_SRC→/media/sd")
  [[ $MOUNT_TERMUX == true ]] && parts+=("Termux:$TERMUX_SRC→/media/termux")
  printf '%s' "${parts[*]:-无额外挂载}"
}

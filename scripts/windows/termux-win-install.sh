#!/data/data/com.termux/files/usr/bin/bash
# termux-win-install.sh —— 安装 Hangover Windows Runtime（M1：ARM64 基础运行时）
#
# 用法:
#   bash termux-win-install.sh            # 安装/修复
#   bash termux-win-install.sh --check    # 只体检，不安装
#
# 设计约束：
#   * 只装官方发布的 deb，SHA-256 校验，版本锁定
#   * 用现有 tmpfs sudo 之外的 root 通道（unshare + chroot）
#   * /dev/shm 在 namespace 内挂载（与桌面启动一致）
#   * Prefix 以 TMOE 主用户创建，绝不用 root
set -uo pipefail

VERSION=11.16
BASE="https://github.com/AndreRH/hangover/releases/download/hangover-$VERSION"
MAIN_TAR="hangover_${VERSION}_ubuntu2604_resolute_arm64.tar"
DLLS_TAR="hangover_${VERSION}_dlls.tar"
SHA_MAIN="bdf7d91d67367a3dc6e856be3c6ab16e8d3b9049e7cd197844df20a7e4b45c52"
SHA_DLLS="645bcdf861db157b9057854c98797cedb477a00723429a1b996450dfb28fc6d2"
MIN_FREE_GB=${MIN_FREE_GB:-8}
CHECK_ONLY=${1:-}

PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
export TMPDIR="$PREFIX/tmp"
export PATH="$PREFIX/bin:$PATH"
BUSYBOX=${BUSYBOX:-/data/adb/ksu/bin/busybox}
SU=$(command -v su || echo /system/bin/su)
STATE="$PREFIX/tmp/termux-gui"
WORK="$PREFIX/tmp/windows-runtime"
mkdir -p "$STATE" "$WORK/downloads" "$WORK/extract" 2>/dev/null

die()  { printf '\033[31m[✗] %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m[✓] %s\033[0m\n' "$*"; }
info() { printf '[*] %s\n' "$*"; }
warn() { printf '\033[33m[!] %s\033[0m\n' "$*"; }

LIB="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/../termux-gui-lib.sh"
[[ -r $LIB ]] || LIB="$HOME/bin/termux-gui-lib.sh"
[[ -r $LIB ]] || die "找不到 termux-gui-lib.sh"
# shellcheck disable=SC1090
source "$LIB"
[[ -n ${CONTAINER:-} ]] || CONTAINER=$(ls -d "$HOME/.local/share/tmoe-linux/containers/chroot"/ubuntu-* 2>/dev/null | head -1)
tmoe_resolve "$CONTAINER" "$BUSYBOX" 2>/dev/null || true

info "容器: $CONTAINER"
info "桌面用户: ${CHROOT_USER:-?}  UID=${USER_UID:-?}"

# ---------- 前置检查 ----------
if [[ -d $CONTAINER/usr/lib/aarch64-linux-gnu || -d $CONTAINER/lib/aarch64-linux-gnu ]]; then ARCH=aarch64; else ARCH=$(uname -m); fi
[[ $ARCH == aarch64 ]] || die "仅支持 arm64，当前: ${ARCH:-未知}"

CODENAME=$(sed -n 's/^VERSION_CODENAME=//p' "$CONTAINER/etc/os-release" 2>/dev/null)
[[ $CODENAME == resolute ]] || die "需要 Ubuntu 26.04 (resolute)，当前: ${CODENAME:-未知}"

FREE_G=$(( $(df -k "$CONTAINER" | awk 'NR==2{print $4}') / 1048576 ))
info "可用空间: ${FREE_G} GB（最低要求 ${MIN_FREE_GB} GB）"
(( FREE_G >= MIN_FREE_GB )) || die "空间不足：需要至少 ${MIN_FREE_GB} GB"

if [[ $CHECK_ONLY == "--check" ]]; then
  ok "体检通过（未做任何修改）"
  exit 0
fi

# ---------- 下载与校验 ----------
fetch() {
  local name=$1 want=$2 out="$WORK/downloads/$1"
  if [[ -f $out ]] && [[ $(sha256sum "$out" | awk '{print $1}') == "$want" ]]; then
    ok "已存在且校验通过: $name"
    return 0
  fi
  info "下载 $name ..."
  for i in 1 2 3; do
    if curl -L --fail --max-time 3600 -C - -o "$out" "$BASE/$name"; then break; fi
    warn "重试 $i"; sleep 3
  done
  local got
  got=$(sha256sum "$out" | awk '{print $1}')
  [[ $got == "$want" ]] || die "SHA-256 不匹配: $name\n  got:  $got\n  want: $want"
  ok "校验通过: $name"
}

fetch "$MAIN_TAR" "$SHA_MAIN"
fetch "$DLLS_TAR" "$SHA_DLLS"

# ---------- 解包 ----------
rm -rf "$WORK/extract"; mkdir -p "$WORK/extract"
tar -xf "$WORK/downloads/$MAIN_TAR" -C "$WORK/extract" || die "解包失败"
tar -xf "$WORK/downloads/$DLLS_TAR" -C "$WORK/extract" || die "dlls 解包失败"
ls "$WORK/extract"/*.deb >/dev/null 2>&1 || die "压缩包内没有 deb，发布物结构可能已变化"

# 拷进容器（/data 上同一文件系统，用 cp 而不是 push）
DEBDIR="$CONTAINER/tmp/windows-runtime/debs"
mkdir -p "$DEBDIR"
cp -f "$WORK/extract"/*.deb "$DEBDIR"/
chown -R "${USER_UID:-0}:${USER_GID:-0}" "$CONTAINER/tmp/windows-runtime" 2>/dev/null || true
ok "deb 已就位: $(ls -1 "$DEBDIR" | wc -l) 个"

# ---------- 安装（root，在私有 namespace 内） ----------
write_shm_helper "$STATE/ensure-dev-shm.sh" 2>/dev/null || true
INSTALLER="$STATE/win-install-root.sh"
cat > "$INSTALLER" <<'EOS'
#!/bin/sh
D=$1; P=$2; BB=$3
"$BB" mount --make-rprivate / || exit 10
"$BB" mount -t proc proc "$D/proc" || exit 12
"$BB" mount -t sysfs sysfs "$D/sys" 2>/dev/null || true
"$BB" mount --bind /dev "$D/dev" || exit 14
"$BB" mount --bind /dev/pts "$D/dev/pts" 2>/dev/null
sh "$P/tmp/termux-gui/ensure-dev-shm.sh" "$D" "$BB" || exit 19
chroot "$D" /usr/bin/env -i \
  HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 \
  /bin/bash -c 'apt-get install -y --no-install-recommends /tmp/windows-runtime/debs/*.deb'
echo "apt_rc=$?"
EOS
chmod 755 "$INSTALLER"
info "安装 deb（可能需要几分钟）..."
if "$SU" -c "sh '$INSTALLER' '$CONTAINER' '$PREFIX' '$BUSYBOX'" 2>&1 | tail -20; then
  ok "APT 安装完成"
else
  die "APT 安装失败，日志见上"
fi

INSTALLED=$(awk '/^Package: hangover-wine$/{f=1} f&&/^Version:/{print $2; exit}' "$CONTAINER/var/lib/dpkg/status" 2>/dev/null)
[[ -n $INSTALLED ]] || die "安装后仍找不到 hangover-wine"
ok "已安装 hangover-wine $INSTALLED"

# ---------- 记录版本 ----------
cat > "$WORK/version.txt" <<EOF
hangover=$INSTALLED
main_tar=$MAIN_TAR sha256=$SHA_MAIN
dlls_tar=$DLLS_TAR sha256=$SHA_DLLS
EOF
"$SU" -c "cp '$WORK/version.txt' '$CONTAINER/etc/termux-win-runtime.version'" || die "写入版本记录失败"
ok "版本记录: /etc/termux-win-runtime.version"

# ---------- Prefix（以桌面用户身份） ----------
PREFIX_DIR="$CONTAINER${USER_HOME:-/home/pad}/.local/share/termux-chroot-desktop/wine/prefixes/default"
if "$SU" -c "test -d '$PREFIX_DIR/drive_c'" 2>/dev/null; then
  ok "Prefix 已存在，跳过初始化"
else
  info "初始化 Prefix（$USER_HOME/.local/share/termux-chroot-desktop/wine）..."
  RUNNER="$STATE/win-prefix-init.sh"
  cat > "$RUNNER" <<'EOS'
#!/bin/sh
D=$1; P=$2; BB=$3; UUID=$4; UGID=$5
"$BB" mount --make-rprivate / || exit 10
"$BB" mount -t proc proc "$D/proc" || exit 12
"$BB" mount -t sysfs sysfs "$D/sys" 2>/dev/null || true
"$BB" mount --bind /dev "$D/dev" || exit 14
"$BB" mount --bind /dev/pts "$D/dev/pts" 2>/dev/null
sh "$P/tmp/termux-gui/ensure-dev-shm.sh" "$D" "$BB" || exit 19
chroot "$D" /usr/bin/env -i HOME=/home/pad USER=pad LOGNAME=pad \
  DISPLAY=:0 MESA_LOADER_DRIVER_OVERRIDE=kgsl XDG_RUNTIME_DIR=/tmp/runtime-pad \
  PULSE_SERVER=tcp:127.0.0.1:4713 LANG=en_US.UTF-8 \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/setpriv --reuid=$UUID --regid=$UGID --init-groups \
  /bin/bash -c 'mkdir -p "$HOME/.local/share/termux-chroot-desktop/wine"/{prefixes,logs,config}; WINEPREFIX="$HOME/.local/share/termux-chroot-desktop/wine/prefixes/default" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" wineboot -u'
echo "wineboot_rc=$?"
EOS
  chmod 755 "$RUNNER"
  "$SU" -c "sh '$RUNNER' '$CONTAINER' '$PREFIX' '$BUSYBOX' '${USER_UID:-1001}' '${USER_GID:-60000}'" 2>&1 | tail -5
  "$SU" -c "test -d '$PREFIX_DIR/drive_c'" 2>/dev/null || die "Prefix 初始化失败"
  ok "Prefix 初始化完成"
fi

ok "Windows Runtime 安装完成"
info "下一步: bash termux-gui-start.sh 启动桌面后运行 Windows 程序（M2 提供统一入口）"

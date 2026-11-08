#!/data/data/com.termux/files/usr/bin/bash
# termux-win-install.sh —— 安装 Hangover Windows Runtime（M1.1）
#
# 用法:
#   bash termux-win-install.sh            # 安装/修复（幂等）
#   bash termux-win-install.sh --check    # 只体检
#
# 设计约束：
#   * 只装官方发布的 deb，SHA-256 校验，版本锁定
#   * 所有 mount 都发生在 unshare -m 之后（含 /dev/shm）
#   * Prefix 以 TMOE 主用户创建，绝不用 root
#   * apt / wineboot 失败必须向上传播，绝不吞退出码
set -uo pipefail

VERSION=11.16
BASE="https://github.com/AndreRH/hangover/releases/download/hangover-$VERSION"
MAIN_TAR="hangover_${VERSION}_ubuntu2604_resolute_arm64.tar"
DLLS_TAR="hangover_${VERSION}_dlls.tar"
SHA_MAIN="bdf7d91d67367a3dc6e856be3c6ab16e8d3b9049e7cd197844df20a7e4b45c52"
SHA_DLLS="645bcdf861db157b9057854c98797cedb477a00723429a1b996450dfb28fc6d2"
DXVK_TAR="dxvk-v2.7.1.tar.gz"
DXVK_SHA="36be8b5803d800abc3f707e36256c77b374a108d73c03a7e34fb42b5f71be8aa"
MIN_FREE_GB=${MIN_FREE_GB:-8}
WIN_SHM_SIZE=${WIN_SHM_SIZE:-256M}
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

UNAME_=${CHROOT_USER:-}
UHOME_=${USER_HOME:-}
UUID_=${USER_UID:-}
UGID_=${USER_GID:-}
[[ -n $UNAME_ && -n $UHOME_ && -n $UUID_ && -n $UGID_ ]] || \
  die "无法解析 TMOE 桌面用户（CHROOT_USER/USER_HOME/UID/GID），拒绝安装"
[[ $UNAME_ != root && $UUID_ -ne 0 ]] || die "桌面用户解析为 root，拒绝用它初始化 Prefix"
[[ -d $CONTAINER$UHOME_ ]] || die "用户 HOME 不存在: $CONTAINER$UHOME_"
PW_ENTRY=$(awk -F: -v u="$UNAME_" '$1==u {print $3":"$4":"$6}' "$CONTAINER/etc/passwd" 2>/dev/null)
[[ $PW_ENTRY == "$UUID_:$UGID_:$UHOME_" ]] || die "passwd 与 TMOE 解析不一致: ${PW_ENTRY:-无此用户} vs $UUID_:$UGID_:$UHOME_"

info "容器: $CONTAINER"
info "桌面用户: $UNAME_  UID=$UUID_  HOME=$UHOME_"

# ---------- 前置检查 ----------
if [[ -d $CONTAINER/usr/lib/aarch64-linux-gnu || -d $CONTAINER/lib/aarch64-linux-gnu ]]; then
  ARCH=aarch64
else
  ARCH=$(uname -m)
fi
[[ $ARCH == aarch64 ]] || die "仅支持 arm64，当前: $ARCH"

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
  local i
  for i in 1 2 3; do
    curl -L --fail --max-time 3600 -C - -o "$out" "$BASE/$name" && break
    warn "重试 $i"; sleep 3
  done
  local got
  got=$(sha256sum "$out" 2>/dev/null | awk '{print $1}')
  [[ $got == "$want" ]] || die "SHA-256 不匹配: $name（got=${got:-缺失} want=$want）"
  ok "校验通过: $name"
}

fetch "$MAIN_TAR" "$SHA_MAIN"
fetch "$DLLS_TAR" "$SHA_DLLS"

# ---------- 解包 ----------
rm -rf "$WORK/extract"; mkdir -p "$WORK/extract"
tar -xf "$WORK/downloads/$MAIN_TAR" -C "$WORK/extract" || die "解包失败"
tar -xf "$WORK/downloads/$DLLS_TAR" -C "$WORK/extract" || die "dlls 解包失败"
ls "$WORK/extract"/*.deb >/dev/null 2>&1 || die "压缩包内没有 deb，发布物结构可能已变化"

DEBDIR="$CONTAINER/tmp/windows-runtime/debs"
mkdir -p "$DEBDIR"
cp -f "$WORK/extract"/*.deb "$DEBDIR"/
chown -R "$UUID_:$UGID_" "$CONTAINER/tmp/windows-runtime" 2>/dev/null || true
ok "deb 已就位: $(ls -1 "$DEBDIR" | wc -l) 个"

# ---------- 安装（root，在私有 namespace 内） ----------
write_shm_helper "$STATE/ensure-dev-shm.sh" || die "无法生成 /dev/shm helper"
INSTALLER="$STATE/win-install-root.sh"
cat > "$INSTALLER" <<'EOS'
#!/bin/sh
D=$1; P=$2; BB=$3; SHM_SIZE=$4
"$BB" mount --make-rprivate / || exit 10
SH=$("$BB" grep -c " shared:" /proc/self/mountinfo)
[ "$SH" = "0" ] || { echo "isolation_failed shared=$SH"; exit 11; }
"$BB" mount -t proc proc "$D/proc" || exit 12
"$BB" mount -t sysfs sysfs "$D/sys" 2>/dev/null || true
"$BB" mount --bind /dev "$D/dev" || exit 14
"$BB" mount --bind /dev/pts "$D/dev/pts" 2>/dev/null
sh "$P/tmp/termux-gui/ensure-dev-shm.sh" "$D" "$BB" "$SHM_SIZE" || exit 19

chroot "$D" /usr/bin/env -i \
  HOME=/root PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 \
  /bin/bash -c 'apt-get install -y --no-install-recommends /tmp/windows-runtime/debs/*.deb'
rc=$?
echo "apt_rc=$rc"
[ "$rc" -eq 0 ] || exit "$rc"

chroot "$D" /usr/bin/env -i \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin LANG=C.UTF-8 \
  /bin/bash -c 'dpkg --audit; apt-get check'
rc=$?
echo "apt_verify_rc=$rc"
[ "$rc" -eq 0 ] || exit "$rc"
EOS
chmod 755 "$INSTALLER"

info "安装 deb（可能需要几分钟）..."
INSTALL_LOG=$("$SU" -c "'$BUSYBOX' unshare -m sh '$INSTALLER' '$CONTAINER' '$PREFIX' '$BUSYBOX' '$WIN_SHM_SIZE'" 2>&1)
INSTALL_RC=$?
printf '%s\n' "$INSTALL_LOG" | tail -20
(( INSTALL_RC == 0 )) || die "APT 安装失败（rc=$INSTALL_RC）"
ok "APT 安装完成"

# 四个包必须都是 install ok installed
PKG_BAD=""
for p in hangover-wine hangover-libarm64ecfex hangover-libwow64fex hangover-wowbox64; do
  st=$(awk -v pkg="$p" '$1=="Package:"{cur=$2} cur==pkg && $1=="Status:"{print; exit}' "$CONTAINER/var/lib/dpkg/status" 2>/dev/null)
  [[ $st == *"install ok installed"* ]] || PKG_BAD="$PKG_BAD $p"
done
[[ -z $PKG_BAD ]] || die "以下包状态异常:$PKG_BAD"
INSTALLED=$(awk '/^Package: hangover-wine$/{f=1} f&&/^Version:/{print $2; exit}' "$CONTAINER/var/lib/dpkg/status" 2>/dev/null)
[[ -n $INSTALLED ]] || die "安装后仍找不到 hangover-wine"
ok "四个包均已安装，hangover-wine $INSTALLED"

# ---------- 记录版本 ----------
cat > "$WORK/version.txt" <<EOF
hangover=$INSTALLED
main_tar=$MAIN_TAR sha256=$SHA_MAIN
dlls_tar=$DLLS_TAR sha256=$SHA_DLLS
dxvk=$DXVK_TAR sha256=$DXVK_SHA (未安装，仅锁定)
EOF
"$SU" -c "cp '$WORK/version.txt' '$CONTAINER/etc/termux-win-runtime.version'" || die "写入版本记录失败"
ok "版本记录: /etc/termux-win-runtime.version"

# ---------- Prefix（以桌面用户身份） ----------
PREFIX_BASE="${WIN_PREFIX_ROOT:-$CONTAINER$UHOME_/.local/share/termux-chroot-desktop/wine}"
PREFIX_DIR="$PREFIX_BASE/prefixes/default"

prefix_owner_ok() {
  local owner
  owner=$("$SU" -c "stat -c %u '$PREFIX_DIR'" 2>/dev/null)
  [[ $owner == "$UUID_" ]]
}

if "$SU" -c "test -d '$PREFIX_DIR/drive_c'" 2>/dev/null; then
  prefix_owner_ok || die "Prefix 已存在但属主不是 $UNAME_($UUID_)，拒绝继续（请修复属主或删除后重试）"
  "$SU" -c "test -f '$PREFIX_DIR/system.reg'" 2>/dev/null || die "Prefix 存在但缺少 system.reg，疑似损坏"
  ok "Prefix 已存在且属主正确，跳过初始化"
else
  info "初始化 Prefix（$UHOME_/.local/share/termux-chroot-desktop/wine）..."
  RUNNER="$STATE/win-prefix-init.sh"
  cat > "$RUNNER" <<'EOS'
#!/bin/sh
D=$1; P=$2; BB=$3; UUID=$4; UGID=$5; UHOME=$6; UNAME=$7; SHM_SIZE=$8
"$BB" mount --make-rprivate / || exit 10
SH=$("$BB" grep -c " shared:" /proc/self/mountinfo)
[ "$SH" = "0" ] || { echo "isolation_failed shared=$SH"; exit 11; }
"$BB" mount -t proc proc "$D/proc" || exit 12
"$BB" mount -t sysfs sysfs "$D/sys" 2>/dev/null || true
"$BB" mount --bind /dev "$D/dev" || exit 14
"$BB" mount --bind /dev/pts "$D/dev/pts" 2>/dev/null
sh "$P/tmp/termux-gui/ensure-dev-shm.sh" "$D" "$BB" "$SHM_SIZE" || exit 19

WP="$UHOME/.local/share/termux-chroot-desktop/wine/prefixes/default"
chroot "$D" /usr/bin/env -i \
  HOME="$UHOME" USER="$UNAME" LOGNAME="$UNAME" \
  DISPLAY=:0 MESA_LOADER_DRIVER_OVERRIDE=kgsl XDG_RUNTIME_DIR="/tmp/runtime-$UNAME" \
  PULSE_SERVER=tcp:127.0.0.1:4713 LANG=en_US.UTF-8 \
  WINEPREFIX="$WP" WINEDEBUG=-all WINEDLLOVERRIDES="mscoree,mshtml=" \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/setpriv --reuid="$UUID" --regid="$UGID" --init-groups \
  /bin/bash -c 'mkdir -p "$HOME/.local/share/termux-chroot-desktop/wine"/{prefixes,logs,config}; wineboot -u'
rc=$?
echo "wineboot_rc=$rc"
[ "$rc" -eq 0 ] || exit "$rc"

chroot "$D" /usr/bin/env -i \
  HOME="$UHOME" USER="$UNAME" LOGNAME="$UNAME" WINEDEBUG=-all \
  WINEPREFIX="$WP" \
  PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  /usr/bin/setpriv --reuid="$UUID" --regid="$UGID" --init-groups \
  /bin/bash -c 'wine cmd /c exit 0'
rc=$?
echo "wine_verify_rc=$rc"
[ "$rc" -eq 0 ] || exit "$rc"
EOS
  chmod 755 "$RUNNER"
  INIT_LOG=$("$SU" -c "'$BUSYBOX' unshare -m sh '$RUNNER' '$CONTAINER' '$PREFIX' '$BUSYBOX' '$UUID_' '$UGID_' '$UHOME_' '$UNAME_' '$WIN_SHM_SIZE'" 2>&1)
  INIT_RC=$?
  printf '%s\n' "$INIT_LOG" | tail -8
  (( INIT_RC == 0 )) || die "Prefix 初始化失败（rc=$INIT_RC）"

  "$SU" -c "test -d '$PREFIX_DIR/drive_c'" 2>/dev/null || die "Prefix 初始化失败：drive_c 不存在"
  "$SU" -c "test -f '$PREFIX_DIR/system.reg'" 2>/dev/null || die "Prefix 初始化失败：system.reg 不存在"
  prefix_owner_ok || die "Prefix 属主异常（应为 $UNAME_ $UUID_）"
  ok "Prefix 初始化完成"
fi

# ---------- 容器内入口 win-run ----------
WINRUN_SRC="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/win-run"
if [[ -r $WINRUN_SRC ]]; then
  "$SU" -c "mkdir -p '$CONTAINER/usr/local/bin'; cp '$WINRUN_SRC' '$CONTAINER/usr/local/bin/win-run'; chmod 755 '$CONTAINER/usr/local/bin/win-run'" \
    || die "安装 win-run 失败"
  ok "已安装 /usr/local/bin/win-run"
else
  warn "未找到 win-run 源文件，跳过"
fi

ok "Windows Runtime 安装完成"
info "下一步: 启动桌面后，容器内用 win-run <app.exe> 运行；Termux 侧用 ~/bin/windows/termux-win-run.sh"

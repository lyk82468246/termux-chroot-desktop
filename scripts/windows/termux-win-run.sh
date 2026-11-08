#!/data/data/com.termux/files/usr/bin/bash
# termux-win-run.sh —— 从 Termux 侧调用容器内的 win-run
#
# 用法:
#   bash termux-win-run.sh /path/to/app.exe [args...]
#   WINRUN_DEBUG=1 bash termux-win-run.sh app.exe
#
# 为什么需要它：
#   attach 会把命令拼进 `sh -c`，空格/引号/中文路径会被破坏。
#   这里改为把 argv 写成 NUL 分隔文件，容器内 win-run 原样读回。
set -uo pipefail

PREFIX=${PREFIX:-/data/data/com.termux/files/usr}
export PATH="$PREFIX/bin:$PATH"

H=$HOME
CACHE="$PREFIX/tmp/termux-win-run"
mkdir -p "$CACHE" 2>/dev/null
chmod 755 "$CACHE" 2>/dev/null

[[ $# -ge 1 ]] || { echo "用法: termux-win-run.sh <app.exe> [args...]" >&2; exit 2; }

ARGV=$(mktemp "$CACHE/argv.XXXXXX") || { echo "无法创建参数文件" >&2; exit 2; }
chmod 644 "$ARGV"

# 工作目录：
#   Termux 的 HOME 是 0700，容器里的 pad 无法进入，因此默认用 /tmp。
#   需要别的目录时用 --dir <容器内路径> 显式指定。
CWD_MAP=/tmp
if [[ ${1:-} == --dir ]]; then
  [[ $# -ge 3 ]] || { echo "--dir 需要参数" >&2; exit 2; }
  CWD_MAP=$2
  shift 2
fi

printf '%s\0' "$CWD_MAP" "$@" > "$ARGV"

REL=${ARGV#"$CACHE"/}
CONTAINER_ARGV="/tmp/termux-win-run/$REL"
CMD="win-run"
[[ ${WINRUN_DEBUG:-0} == 1 ]] && CMD="win-run --debug"
CMD="$CMD --argv-file '$CONTAINER_ARGV'"

ATTACH="$H/bin/termux-gui-attach.sh"
[[ -r $ATTACH ]] || { rm -f "$ARGV"; echo "找不到 $ATTACH" >&2; exit 2; }

"${BASH:-$PREFIX/bin/bash}" "$ATTACH" $CMD
RC=$?
rm -f "$ARGV"
exit $RC

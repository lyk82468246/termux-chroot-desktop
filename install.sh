#!/data/data/com.termux/files/usr/bin/bash
# 安装脚本到 ~/bin；可选安装 Termux:Widget 入口
#
# 用法:
#   bash install.sh            # 只装脚本
#   bash install.sh --widget   # 同时创建 ~/.shortcuts 里的 Widget 入口
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="${DEST:-$HOME/bin}"

mkdir -p "$DEST"
for f in termux-gui-lib.sh termux-gui-start.sh termux-gui-stop.sh termux-gui-attach.sh; do
  cp "$SRC/scripts/$f" "$DEST/$f"
done
chmod 755 "$DEST"/termux-gui-start.sh "$DEST"/termux-gui-stop.sh "$DEST"/termux-gui-attach.sh
chmod 644 "$DEST"/termux-gui-lib.sh

echo "已安装到 $DEST："
ls -l "$DEST"/termux-gui-*.sh

# ---------- Termux:Widget 入口 ----------
if [[ ${1:-} == "--widget" ]]; then
  SH="$HOME/.shortcuts"
  TASKS="$SH/tasks"
  mkdir -p "$TASKS"

  write_entry() {
    local path=$1 target=$2
    cat > "$path" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
# Termux:Widget -> $DEST/$target
export HOME="$HOME"
export PREFIX="\${PREFIX:-/data/data/com.termux/files/usr}"
exec "$DEST/$target" "\$@"
EOF
    chmod 755 "$path"
  }

  # 后台型：不弹终端窗口，适合 start / stop
  write_entry "$TASKS/start-desktop" termux-gui-start.sh
  write_entry "$TASKS/stop-desktop"  termux-gui-stop.sh
  # 前台型：需要交互，放 ~/.shortcuts
  write_entry "$SH/attach-terminal"  termux-gui-attach.sh

  echo
  echo "Widget 入口已创建："
  ls -l "$TASKS" "$SH"
  echo
  echo "在桌面添加 Termux:Widget，里面会出现：start-desktop / stop-desktop / attach-terminal"
fi

cat <<'EOF'

下一步：
  bash ~/bin/termux-gui-start.sh        # 启动桌面
  bash ~/bin/termux-gui-attach.sh       # 进容器终端
  bash ~/bin/termux-gui-stop.sh         # 停止

可选：
  COMPOSITOR=picom bash ~/bin/termux-gui-start.sh   # 开窗口阴影
  DESKTOP_AS_ROOT=1 bash ~/bin/termux-gui-start.sh  # 桌面用 root
EOF

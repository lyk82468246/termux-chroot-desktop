#!/data/data/com.termux/files/usr/bin/bash
# 安装脚本到 ~/bin
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

cat <<'EOF'

下一步：
  bash ~/bin/termux-gui-start.sh        # 启动桌面
  bash ~/bin/termux-gui-attach.sh       # 进容器终端
  bash ~/bin/termux-gui-stop.sh         # 停止

可选：
  COMPOSITOR=picom bash ~/bin/termux-gui-start.sh   # 开窗口阴影
  DESKTOP_AS_ROOT=1 bash ~/bin/termux-gui-start.sh  # 桌面用 root
EOF

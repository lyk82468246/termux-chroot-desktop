#!/bin/bash
export WINEPREFIX="$HOME/.local/share/termux-chroot-desktop/wine/prefixes/default"
export WINEDEBUG=-all DISPLAY=:0
count_ws() { local n=0 d c; for d in /proc/[0-9]*; do c=$(cat "$d/comm" 2>/dev/null) || continue; [ "$c" = "wineserver" ] && n=$((n+1)); done; echo $n; }
pids() { local pat=$1 d cmd; for d in /proc/[0-9]*/cmdline; do [ -r "$d" ] || continue; cmd=$(tr '\0' ' ' < "$d" 2>/dev/null); case "$cmd" in *"$pat"*) d=${d#/proc/}; echo "${d%/cmdline}";; esac; done; }
cnt_notepad() { pids "notepad.exe" | wc -l; }
cnt_x64() { local d cmd n=0; for d in /proc/[0-9]*/cmdline; do [ -r "$d" ] || continue; cmd=$(tr '\0' ' ' < "$d" 2>/dev/null); case "$cmd" in *gui_test.exe*) case "$cmd" in *ia32*) ;; *) n=$((n+1));; esac;; esac; done; echo $n; }
cnt_x86() { local d cmd n=0; for d in /proc/[0-9]*/cmdline; do [ -r "$d" ] || continue; cmd=$(tr '\0' ' ' < "$d" 2>/dev/null); case "$cmd" in *ia32*gui_test.exe*) n=$((n+1));; esac; done; echo $n; }
wait3() { local i=0; while [ $i -lt 120 ]; do [ "$(cnt_notepad)" -ge 1 ] && [ "$(cnt_x64)" -ge 1 ] && [ "$(cnt_x86)" -ge 1 ] && return 0; sleep 1; i=$((i+1)); done; return 1; }

start_all() {
  win-run /usr/lib/wine/aarch64-windows/notepad.exe > /tmp/m32-np.log 2>&1 &
  win-run /tmp/win-tests/gui_test.exe --exit-after 300000 > /tmp/m32-g64.log 2>&1 &
  win-run /tmp/win-tests/ia32/gui_test.exe --exit-after 300000 > /tmp/m32-g86.log 2>&1 &
}

echo "=== 场景 A：三架构同时运行 ==="
wineserver -k 2>/dev/null; sleep 1
start_all
wait3 && echo "三架构就绪: notepad=$(cnt_notepad) x64=$(cnt_x64) x86=$(cnt_x86) ws=$(count_ws)" || echo "未全部就绪: np=$(cnt_notepad) x64=$(cnt_x64) x86=$(cnt_x86) ws=$(count_ws)"

echo "=== 顺序一：ARM64 → AMD64 → I386 ==="
kill $(pids "notepad.exe" | head -1) 2>/dev/null; sleep 3
echo "关 ARM64 后: np=$(cnt_notepad) x64=$(cnt_x64) x86=$(cnt_x86) ws=$(count_ws)"
kill $(pids "gui_test.exe" | grep -v -f <(pids "ia32") | head -1) 2>/dev/null; sleep 3
echo "关 AMD64 后: np=$(cnt_notepad) x64=$(cnt_x64) x86=$(cnt_x86) ws=$(count_ws)"
for p in $(pids "ia32"); do kill "$p" 2>/dev/null; done; sleep 3
echo "关 I386 后: np=$(cnt_notepad) x64=$(cnt_x64) x86=$(cnt_x86) ws=$(count_ws)"
wineserver -k 2>/dev/null; sleep 1

echo "=== 顺序二：I386 → ARM64 → AMD64 ==="
start_all
wait3 && echo "三架构就绪: np=$(cnt_notepad) x64=$(cnt_x64) x86=$(cnt_x86) ws=$(count_ws)"
for p in $(pids "ia32"); do kill "$p" 2>/dev/null; done; sleep 3
echo "关 I386 后: np=$(cnt_notepad) x64=$(cnt_x64) x86=$(cnt_x86) ws=$(count_ws)"
kill $(pids "notepad.exe" | head -1) 2>/dev/null; sleep 3
echo "关 ARM64 后: np=$(cnt_notepad) x64=$(cnt_x64) x86=$(cnt_x86) ws=$(count_ws)"
kill $(pids "gui_test.exe" | grep -v -f <(pids "ia32") | head -1) 2>/dev/null; sleep 3
echo "关 AMD64 后: np=$(cnt_notepad) x64=$(cnt_x64) x86=$(cnt_x86) ws=$(count_ws)"
wineserver -k 2>/dev/null
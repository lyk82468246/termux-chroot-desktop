#!/bin/bash
# 编译 IA-32 (I386) 测试程序，需要 i686-w64-mingw32-gcc
set -e
cd "$(dirname "$0")"
G=i686-w64-mingw32-gcc
$G -O2 -o hello.exe      hello.c      -mconsole
$G -O2 -o args_test.exe  ../args_test.c -municode -mconsole
$G -O2 -o file_test.exe  file_test.c  -mconsole
$G -O2 -o gui_test.exe   gui32_test.c -lgdi32 -mwindows
$G -O2 -o probe.exe      probe.c      -lgdi32 -luser32 -mwindows
ls -l *.exe
python3 - <<'PY'
import struct, glob
for p in sorted(glob.glob('*.exe')):
    d = open(p, 'rb').read(0x400)
    off = struct.unpack_from('<I', d, 0x3c)[0]
    m = struct.unpack_from('<H', d, off + 4)[0]
    print("%s: machine=0x%04x" % (p, m))
PY

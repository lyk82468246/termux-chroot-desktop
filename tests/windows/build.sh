#!/bin/bash
# ?? Windows ?????????????? gcc-mingw-w64-x86-64?
set -e
cd "$(dirname "$0")"
x86_64-w64-mingw32-gcc -O2 -o gui_test.exe  gui_test.c  -lgdi32 -mwindows
x86_64-w64-mingw32-gcc -O2 -o args_test.exe args_test.c -municode -mconsole
ls -l gui_test.exe args_test.exe
python3 - <<'PY'
import struct,glob
for p in sorted(glob.glob('*.exe')):
    d=open(p,'rb').read(0x400); off=struct.unpack_from('<I',d,0x3c)[0]
    m=struct.unpack_from('<H',d,off+4)[0]
    print(f"{p}: machine=0x{m:04x}")
PY

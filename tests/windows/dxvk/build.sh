#!/bin/bash
set -e
cd "$(dirname "$0")"
x86_64-w64-mingw32-gcc -O2 -o d3d11_test.exe d3d11_test.c \
  -ld3d11 -ldxgi -ld3dcompiler -luser32 -lgdi32 -mconsole
ls -l d3d11_test.exe
python3 - <<'PY'
import struct
d = open("d3d11_test.exe", "rb").read(0x400)
off = struct.unpack_from("<I", d, 0x3c)[0]
m = struct.unpack_from("<H", d, off + 4)[0]
print("machine=0x%04x" % m)
PY

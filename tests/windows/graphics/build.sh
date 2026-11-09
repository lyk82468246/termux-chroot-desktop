#!/bin/bash
# ?? D3D9/D3D10/D3D11 ?????x64 + x86?
set -e
cd "$(dirname "$0")"
G64=x86_64-w64-mingw32-gcc
G32=i686-w64-mingw32-gcc

$G64 -O2 -o d3d9_x64.exe  d3d9_test.c  -ld3d9  -luser32 -lgdi32 -mconsole
$G32 -O2 -o d3d9_x86.exe  d3d9_test.c  -ld3d9  -luser32 -lgdi32 -mconsole
$G64 -O2 -o d3d10_x64.exe d3d10_test.c -ld3d10 -ldxgi -ld3dcompiler -luser32 -lgdi32 -mconsole
$G32 -O2 -o d3d10_x86.exe d3d10_test.c -ld3d10 -ldxgi -ld3dcompiler -luser32 -lgdi32 -mconsole
$G64 -O2 -o d3d11_x64.exe ../dxvk/d3d11_test.c -ld3d11 -ldxgi -ld3dcompiler -luser32 -lgdi32 -mconsole
$G32 -O2 -o d3d11_x86.exe ../dxvk/d3d11_test.c -ld3d11 -ldxgi -ld3dcompiler -luser32 -lgdi32 -mconsole
$G64 -O2 -o gl_probe_x64.exe gl_probe.c -lopengl32 -lgdi32 -luser32 -mconsole
$G32 -O2 -o gl_probe_x86.exe gl_probe.c -lopengl32 -lgdi32 -luser32 -mconsole
ls -l *.exe
python3 - <<'PY'
import struct, glob
for p in sorted(glob.glob('*.exe')):
    d = open(p, 'rb').read(0x400)
    off = struct.unpack_from('<I', d, 0x3c)[0]
    m = struct.unpack_from('<H', d, off + 4)[0]
    print("%s machine=0x%04x" % (p, m))
PY

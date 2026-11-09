#!/bin/bash
set -e
cd "$(dirname "$0")"
G="glslangValidator -V --target-env vulkan1.1"
$G vert.vert      -o vert.spv
$G vert0.vert     -o vert0.spv
$G vert1.vert     -o vert1.spv
$G vert_pass.vert -o vert_pass.spv
$G geom1.geom     -o geom1.spv
$G frag.frag      -o frag.spv
gcc -O2 -o vulkan_mv vulkan_mv.c -lvulkan -lm
ls -l vulkan_mv *.spv

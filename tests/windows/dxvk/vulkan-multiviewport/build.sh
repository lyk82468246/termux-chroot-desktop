#!/bin/bash
set -e
cd "$(dirname "$0")"
glslangValidator -V --target-env vulkan1.1 vert.vert -o vert.spv
glslangValidator -V --target-env vulkan1.1 frag.frag -o frag.spv
gcc -O2 -o vulkan_mv vulkan_mv.c -lvulkan -lm
ls -l vulkan_mv vert.spv frag.spv

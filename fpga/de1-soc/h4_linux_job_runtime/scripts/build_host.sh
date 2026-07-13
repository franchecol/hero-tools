#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h4_dir=$(cd -- "${script_dir}/.." && pwd)
mkdir -p "${h4_dir}/build"

clang --target=armv7a-linux-gnueabihf -fuse-ld=lld \
  -nostdlib -static -nostartfiles -fno-builtin -fno-stack-protector -O2 \
  -I "${h4_dir}/include" -Wl,-e,_start -Wl,--build-id=none \
  "${h4_dir}/sw/h4_host_nolibc.c" -o "${h4_dir}/build/h4_host_nolibc"
file "${h4_dir}/build/h4_host_nolibc"

#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h0_dir=$(cd -- "${script_dir}/.." && pwd)
mkdir -p "${h0_dir}/build"

clang --target=armv7a-linux-gnueabihf -fuse-ld=lld \
  -nostdlib -static -fno-builtin -fno-stack-protector -O2 \
  -Wall -Wextra -Werror -Wl,-e,_start -Wl,--build-id=none \
  "${h0_dir}/sw/h0_5_read_only_probe.c" \
  -o "${h0_dir}/build/h0_5_read_only_probe"
file "${h0_dir}/build/h0_5_read_only_probe"

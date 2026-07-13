#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h6_dir=$(cd -- "${script_dir}/.." && pwd)
mkdir -p "${h6_dir}/build"
clang --target=arm-linux-gnueabihf -march=armv7-a -mfloat-abi=soft \
  -Oz -ffreestanding -fno-builtin -fno-stack-protector -nostdlib -static \
  -Wl,-e,_start -I"${h6_dir}/include" "${h6_dir}/sw/h6_client_nolibc.c" \
  -o "${h6_dir}/build/h6_client_nolibc"
file "${h6_dir}/build/h6_client_nolibc"

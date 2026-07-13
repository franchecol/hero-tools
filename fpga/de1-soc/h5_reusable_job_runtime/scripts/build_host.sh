#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h5_dir=$(cd -- "${script_dir}/.." && pwd)
h4_dir=$(cd -- "${h5_dir}/../h4_linux_job_runtime" && pwd)
mkdir -p "${h5_dir}/build"
clang --target=arm-linux-gnueabihf -march=armv7-a -mfloat-abi=soft \
  -Oz -ffreestanding -fno-builtin -fno-stack-protector -nostdlib -static -Wl,-e,_start \
  -I"${h4_dir}/include" "${h5_dir}/sw/h5_host_nolibc.c" \
  -o "${h5_dir}/build/h5_host_nolibc"
file "${h5_dir}/build/h5_host_nolibc"

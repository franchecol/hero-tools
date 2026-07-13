#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h3_dir=$(cd -- "${script_dir}/.." && pwd)
mkdir -p "${h3_dir}/build"

riscv64-unknown-elf-gcc -march=rv32ima -mabi=ilp32 -nostdlib \
  -Wl,--build-id=none -T "${h3_dir}/firmware/shared_transform.ld" \
  "${h3_dir}/firmware/shared_transform.S" \
  -o "${h3_dir}/build/shared_transform.elf"
riscv64-unknown-elf-objcopy -O binary \
  "${h3_dir}/build/shared_transform.elf" "${h3_dir}/build/shared_transform.bin"
riscv64-unknown-elf-objdump -d "${h3_dir}/build/shared_transform.elf" \
  > "${h3_dir}/build/shared_transform.dump"
test "$(stat -c %s "${h3_dir}/build/shared_transform.bin")" -le 4096

#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h4_dir=$(cd -- "${script_dir}/.." && pwd)
mkdir -p "${h4_dir}/build"

riscv64-unknown-elf-gcc -march=rv32ima -mabi=ilp32 -nostdlib \
  -I "${h4_dir}/include" -Wl,--build-id=none \
  -T "${h4_dir}/firmware/h4_job.ld" "${h4_dir}/firmware/h4_job.S" \
  -o "${h4_dir}/build/h4_job.elf"
riscv64-unknown-elf-objcopy -O binary \
  "${h4_dir}/build/h4_job.elf" "${h4_dir}/build/h4_job.bin"
riscv64-unknown-elf-objdump -d "${h4_dir}/build/h4_job.elf" \
  > "${h4_dir}/build/h4_job.dump"
test "$(stat -c %s "${h4_dir}/build/h4_job.bin")" -le 4096

#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h7_dir=$(cd -- "${script_dir}/.." && pwd)
h4_dir=$(cd -- "${h7_dir}/../h4_linux_job_runtime" && pwd)
mkdir -p "${h7_dir}/build"
riscv64-unknown-elf-gcc -march=rv32ima -mabi=ilp32 -nostdlib -nostartfiles \
  -I"${h4_dir}/include" -T "${h7_dir}/firmware/resident_job.ld" \
  "${h7_dir}/firmware/resident_job.S" -o "${h7_dir}/build/resident_job.elf"
riscv64-unknown-elf-objcopy -O binary "${h7_dir}/build/resident_job.elf" \
  "${h7_dir}/build/resident_job.bin"
riscv64-unknown-elf-objdump -d "${h7_dir}/build/resident_job.elf" \
  > "${h7_dir}/build/resident_job.dump"
test "$(stat -c %s "${h7_dir}/build/resident_job.bin")" -le 4096
echo H7_RESIDENT_FIRMWARE_BUILD_PASS

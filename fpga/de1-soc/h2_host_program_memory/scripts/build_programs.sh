#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h2_dir=$(cd -- "${script_dir}/.." && pwd)
firmware="${h2_dir}/../h0_7_observable_boot/firmware"
mkdir -p "${h2_dir}/build"

build_one() {
  local tag=$1 signature=$2
  riscv64-unknown-elf-gcc -march=rv32ima -mabi=ilp32 -nostdlib \
    -DSIGNATURE="${signature}" -Wl,--build-id=none -T "${firmware}/boot.ld" \
    "${firmware}/boot_store.S" -o "${h2_dir}/build/${tag}.elf"
  riscv64-unknown-elf-objcopy -O binary "${h2_dir}/build/${tag}.elf" \
    "${h2_dir}/build/${tag}.bin"
  riscv64-unknown-elf-objdump -d "${h2_dir}/build/${tag}.elf" \
    > "${h2_dir}/build/${tag}.dump"
  test "$(stat -c %s "${h2_dir}/build/${tag}.bin")" -le 4096
}

build_one program_5a5 0x5a5
build_one program_3c3 0x3c3

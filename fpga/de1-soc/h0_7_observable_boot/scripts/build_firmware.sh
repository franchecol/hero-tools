#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h0_dir=$(cd -- "${script_dir}/.." && pwd)
mkdir -p "${h0_dir}/build"

riscv64-unknown-elf-gcc -march=rv32ima -mabi=ilp32 -nostdlib \
  -Wl,--build-id=none -T "${h0_dir}/firmware/boot.ld" \
  "${h0_dir}/firmware/boot_store.S" -o "${h0_dir}/build/boot_store.elf"
riscv64-unknown-elf-objcopy -O binary \
  "${h0_dir}/build/boot_store.elf" "${h0_dir}/build/boot_store.bin"
riscv64-unknown-elf-objdump -d \
  "${h0_dir}/build/boot_store.elf" > "${h0_dir}/build/boot_store.dump"

test "$(stat -c %s "${h0_dir}/build/boot_store.bin")" -eq 16
actual_words=$(od -An -tx4 -v "${h0_dir}/build/boot_store.bin" | xargs)
expected_words="000022b7 5a500313 0062a023 0000006f"
test "${actual_words}" = "${expected_words}"
cat "${h0_dir}/build/boot_store.dump"

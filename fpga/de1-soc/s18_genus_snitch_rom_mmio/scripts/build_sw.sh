#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s18_dir=$(cd -- "${script_dir}/.." && pwd)
out_dir="${s18_dir}/generated/sw"
rom_file="${s18_dir}/generated/rom_words.svh"

prefix=${RISCV_PREFIX:-riscv64-unknown-elf}
if ! command -v "${prefix}-gcc" >/dev/null 2>&1; then
    prefix=riscv64-elf
fi

mkdir -p "${out_dir}"

"${prefix}-gcc" \
    -march=rv32e \
    -mabi=ilp32e \
    -mcmodel=medany \
    -nostdlib \
    -nostartfiles \
    -Wl,-T,"${s18_dir}/sw/link.ld" \
    -Wl,-Map,"${out_dir}/led_mmio.map" \
    "${s18_dir}/sw/led_mmio.S" \
    -o "${out_dir}/led_mmio.elf"

"${prefix}-objdump" -d "${out_dir}/led_mmio.elf" \
    > "${out_dir}/led_mmio.dump"
"${prefix}-objcopy" -O binary -j .text \
    "${out_dir}/led_mmio.elf" \
    "${out_dir}/led_mmio.bin"

python3 "${script_dir}/bin_to_rom_svh.py" \
    "${out_dir}/led_mmio.bin" \
    "${rom_file}"

test "$(stat -c %s "${out_dir}/led_mmio.bin")" -eq 16
grep -Fq "32'h400002b7" "${rom_file}"
grep -Fq "32'h15500313" "${rom_file}"
grep -Fq "32'h0062a023" "${rom_file}"
grep -Fq "32'h0000006f" "${rom_file}"

#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s19_dir=$(cd -- "${script_dir}/.." && pwd)
out_dir="${s19_dir}/generated/sw"
rom_file="${s19_dir}/generated/rom_words.svh"

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
    -Wl,-T,"${s19_dir}/sw/link.ld" \
    -Wl,-Map,"${out_dir}/ram_check.map" \
    "${s19_dir}/sw/ram_check.S" \
    -o "${out_dir}/ram_check.elf"

"${prefix}-objdump" -d "${out_dir}/ram_check.elf" \
    > "${out_dir}/ram_check.dump"
"${prefix}-objcopy" -O binary -j .text \
    "${out_dir}/ram_check.elf" \
    "${out_dir}/ram_check.bin"

python3 "${script_dir}/bin_to_rom_svh.py" \
    "${out_dir}/ram_check.bin" \
    "${rom_file}"

test "$(stat -c %s "${out_dir}/ram_check.bin")" -eq 56
grep -Fq "sw" "${out_dir}/ram_check.dump"
grep -Fq "lw" "${out_dir}/ram_check.dump"
grep -Fq "bne" "${out_dir}/ram_check.dump"

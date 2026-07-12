#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h0_dir=$(cd -- "${script_dir}/.." && pwd)
mkdir -p "${h0_dir}/build"
verilator --binary --timing --assert -Wno-fatal \
  --top-module axi_boot_rom_tb \
  --Mdir "${h0_dir}/build/obj_dir" \
  "${h0_dir}/rtl/axi_boot_rom.sv" \
  "${h0_dir}/tb/axi_boot_rom_tb.sv"
"${h0_dir}/build/obj_dir/Vaxi_boot_rom_tb"

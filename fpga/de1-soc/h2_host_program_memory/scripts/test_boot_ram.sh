#!/usr/bin/env bash
set -euo pipefail
dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "${dir}/build"
verilator --binary --timing --assert -Wno-fatal --top-module axi_boot_ram_tb \
  --Mdir "${dir}/build/obj_dir" "${dir}/rtl/axi_boot_ram.sv" "${dir}/tb/axi_boot_ram_tb.sv"
"${dir}/build/obj_dir/Vaxi_boot_ram_tb"

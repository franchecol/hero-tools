#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h3_dir=$(cd -- "${script_dir}/.." && pwd)
mkdir -p "${h3_dir}/build"

verilator --binary --timing --assert -Wno-fatal \
  --top-module axi_shared_data_ram_tb \
  --Mdir "${h3_dir}/build/obj_dir" \
  "${h3_dir}/rtl/axi_shared_data_ram.sv" \
  "${h3_dir}/tb/axi_shared_data_ram_tb.sv"
"${h3_dir}/build/obj_dir/Vaxi_shared_data_ram_tb"

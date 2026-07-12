#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h0_dir=$(cd -- "${script_dir}/.." && pwd)
mkdir -p "${h0_dir}/build"

verilator --binary --timing --assert -Wno-fatal \
    --top-module avalon_to_narrow_axi_tb \
    --Mdir "${h0_dir}/build/obj_dir" \
    "${h0_dir}/rtl/avalon_to_narrow_axi.sv" \
    "${h0_dir}/tb/avalon_to_narrow_axi_tb.sv"
"${h0_dir}/build/obj_dir/Vavalon_to_narrow_axi_tb"

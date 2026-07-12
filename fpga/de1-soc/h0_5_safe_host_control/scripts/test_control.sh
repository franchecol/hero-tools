#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h0_dir=$(cd -- "${script_dir}/.." && pwd)
mkdir -p "${h0_dir}/build"

verilator --binary --timing --assert -Wno-fatal \
  --top-module safe_host_control_tb \
  --Mdir "${h0_dir}/build/obj_dir" \
  "${h0_dir}/rtl/safe_host_control.sv" \
  "${h0_dir}/tb/safe_host_control_tb.sv"
"${h0_dir}/build/obj_dir/Vsafe_host_control_tb"

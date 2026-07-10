#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s18_dir=$(cd -- "${script_dir}/.." && pwd)
s17_dir=$(cd -- "${s18_dir}/../u0_genus_snitch_core" && pwd)
source_netlist="${s17_dir}/build/snitch_core_generic_netlist.v"
quartus_netlist="${s17_dir}/build/snitch_core_generic_quartus.v"

"${script_dir}/build_sw.sh"
python3 "${s17_dir}/scripts/sanitize_genus_identifiers.py" \
    "${source_netlist}" \
    "${quartus_netlist}"

rm -rf "${s18_dir}/generated/verilator"
verilator \
    --binary \
    --timing \
    -Wno-fatal \
    -Wno-IMPLICIT \
    --top-module de1_s18_genus_snitch_rom_mmio_tb \
    -I"${s18_dir}/generated" \
    --Mdir "${s18_dir}/generated/verilator" \
    "${quartus_netlist}" \
    "${s18_dir}/rtl/de1_s18_genus_snitch_rom_mmio.sv" \
    "${s18_dir}/tb/de1_s18_genus_snitch_rom_mmio_tb.sv"

"${s18_dir}/generated/verilator/Vde1_s18_genus_snitch_rom_mmio_tb"

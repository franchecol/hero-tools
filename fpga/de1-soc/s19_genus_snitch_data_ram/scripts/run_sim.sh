#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
s19_dir=$(cd -- "${script_dir}/.." && pwd)
source_netlist="${s19_dir}/build/snitch_mem_generic_netlist.v"
quartus_netlist="${s19_dir}/build/snitch_mem_generic_quartus.v"
expected=558f10a2df2b65d74f35532d985ad892e035d8873cd306b1f5c3de107807d882

"${script_dir}/build_sw.sh"

if [[ ! -f "${source_netlist}" ]]; then
    echo "Missing S19 Genus netlist. Run deploy_and_run_lab.sh and fetch_netlist.sh." >&2
    exit 1
fi


actual=$(sha256sum "${source_netlist}" | awk '{print $1}')
if [[ "${actual}" != "${expected}" ]]; then
    echo "Unexpected S19 generic netlist SHA-256: ${actual}" >&2
    exit 1
fi

python3 "${s19_dir}/../s17_genus_snitch_core/scripts/sanitize_genus_identifiers.py" \
    "${source_netlist}" \
    "${quartus_netlist}"

rm -rf "${s19_dir}/generated/verilator"
verilator \
    --binary \
    --timing \
    -Wno-fatal \
    -Wno-IMPLICIT \
    -Wno-TIMESCALEMOD \
    -Wno-MULTIDRIVEN \
    --top-module de1_s19_genus_snitch_data_ram_tb \
    -I"${s19_dir}/generated" \
    --Mdir "${s19_dir}/generated/verilator" \
    "${quartus_netlist}" \
    "${s19_dir}/rtl/de1_s19_genus_snitch_data_ram.sv" \
    "${s19_dir}/tb/de1_s19_genus_snitch_data_ram_tb.sv"

"${s19_dir}/generated/verilator/Vde1_s19_genus_snitch_data_ram_tb"

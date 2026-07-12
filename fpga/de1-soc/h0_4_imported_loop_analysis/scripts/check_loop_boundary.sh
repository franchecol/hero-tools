#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(cd -- "${script_dir}/../../../../" && pwd)
netlist="${root}/fpga/de1-soc/u4_cyclone_memory_boundary/generated/de1_u4_cluster_quartus.v"
sta_report="${root}/fpga/de1-soc/h0_3_de1_upstream_fit/output_files/de1_h0_3_upstream_cluster.sta.rpt"

test -f "${netlist}"
test -f "${sta_report}"

count=$(grep -c 'i_idq_cdn_loop_breaker' "${netlist}")
if [[ "${count}" -ne 1 ]]; then
  printf 'ERROR: expected one named ID-queue loop marker, found %s.\n' "${count}" >&2
  exit 1
fi

if grep -q 'Design contains combinational loop' "${sta_report}"; then
  printf 'ERROR: Quartus still reports a combinational timing loop.\n' >&2
  exit 1
fi

printf 'H0.4_LOOP_BOUNDARY_PASS\n'

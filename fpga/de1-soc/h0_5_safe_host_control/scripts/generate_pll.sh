#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h0_dir=$(cd -- "${script_dir}/.." && pwd)
output_dir="${h0_dir}/generated/cluster_pll"

rm -rf "${output_dir}"
mkdir -p "${output_dir}"
ip-generate --component-name=altera_pll \
  --file-set=QUARTUS_SYNTH \
  --system-info=DEVICE_FAMILY="Cyclone V" \
  --part=5CSEMA5F31C6 \
  --component-parameter=gui_reference_clock_frequency=50.0 \
  --component-parameter=gui_number_of_clocks=1 \
  --component-parameter=gui_output_clock_frequency0=15.0 \
  --output-name=cluster_pll \
  --output-directory="${output_dir}" \
  --standard-reports
test -f "${output_dir}/cluster_pll.v"

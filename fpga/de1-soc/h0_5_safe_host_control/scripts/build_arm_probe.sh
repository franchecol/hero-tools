#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h0_dir=$(cd -- "${script_dir}/.." && pwd)
mkdir -p "${h0_dir}/build"

arm-linux-gnueabihf-gcc -fno-link-libatomic -O2 -Wall -Wextra -Werror \
  "${h0_dir}/sw/h0_5_read_only_probe.c" \
  -o "${h0_dir}/build/h0_5_read_only_probe"
file "${h0_dir}/build/h0_5_read_only_probe"
arm-linux-gnueabihf-readelf -l "${h0_dir}/build/h0_5_read_only_probe" | \
  grep 'Requesting program interpreter'

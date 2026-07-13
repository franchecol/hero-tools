#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h4_dir=$(cd -- "${script_dir}/.." && pwd)

"${script_dir}/build_firmware.sh"
"${script_dir}/build_host.sh"

riscv64-unknown-elf-readelf -h "${h4_dir}/build/h4_job.elf" | \
  grep -q 'Machine:.*RISC-V'
readelf -h "${h4_dir}/build/h4_host_nolibc" | grep -q 'Machine:.*ARM'
grep -q 'H4_JOB_RUNTIME_PASS' "${h4_dir}/sw/h4_host_nolibc.c"
grep -q '4834' "${h4_dir}/build/h4_job.dump"
printf 'H4_JOB_ABI_BUILD_PASS\n'

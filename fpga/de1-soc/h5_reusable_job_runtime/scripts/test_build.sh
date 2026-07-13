#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h5_dir=$(cd -- "${script_dir}/.." && pwd)
h4_dir=$(cd -- "${h5_dir}/../h4_linux_job_runtime" && pwd)
"${h4_dir}/scripts/test_abi.sh"
"${script_dir}/build_host.sh"
file "${h5_dir}/build/h5_host_nolibc" | grep -q 'ELF 32-bit LSB executable, ARM'
strings "${h5_dir}/build/h5_host_nolibc" | grep -q 'H5_REUSABLE_RUNTIME_PASS'
echo H5_REUSABLE_RUNTIME_BUILD_PASS

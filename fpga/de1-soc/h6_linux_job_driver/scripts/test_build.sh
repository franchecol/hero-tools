#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h6_dir=$(cd -- "${script_dir}/.." && pwd)
h4_dir=$(cd -- "${h6_dir}/../h4_linux_job_runtime" && pwd)
"${h4_dir}/scripts/build_firmware.sh"
"${script_dir}/build_driver.sh"
"${script_dir}/build_client.sh"
file "${h6_dir}/build/snitch_job.ko" | grep -q 'ELF 32-bit LSB relocatable, ARM'
file "${h6_dir}/build/h6_client_nolibc" | grep -q 'ELF 32-bit LSB executable, ARM'
strings "${h6_dir}/build/h6_client_nolibc" | grep -q 'H6_LINUX_JOB_DRIVER_PASS'
echo H6_LINUX_JOB_DRIVER_BUILD_PASS

#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h7_dir=$(cd -- "${script_dir}/.." && pwd)
h6_dir=$(cd -- "${h7_dir}/../h6_linux_job_driver" && pwd)
"${script_dir}/build_firmware.sh"
"${h6_dir}/scripts/build_driver.sh"
"${h6_dir}/scripts/build_client.sh"
strings "${h6_dir}/build/h6_client_nolibc" | grep -q H7_RESIDENT_WORKER_PASS
grep -q '<wait_for_job>' "${h7_dir}/build/resident_job.dump"
grep -q '<wait_for_release>' "${h7_dir}/build/resident_job.dump"
echo H7_RESIDENT_STACK_BUILD_PASS

#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h6_dir=$(cd -- "${script_dir}/.." && pwd)
kernel_src="${KERNEL_SRC:-/home/ftv/builds/kernel-src/linux-socfpga-altera-4.5}"
toolchain="${TOOLCHAIN:-/home/ftv/builds/toolchains/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf}"
cross_compile="${CROSS_COMPILE:-${toolchain}/bin/arm-linux-gnueabihf-}"
localversion="${LOCALVERSION:--00183-g4647b69-dirty}"
expected_release="${EXPECTED_RELEASE:-4.5.0-00183-g4647b69-dirty}"

release=$(make -s -C "${kernel_src}" ARCH=arm CROSS_COMPILE="${cross_compile}" \
  LOCALVERSION="${localversion}" HOSTCFLAGS=-fcommon kernelrelease)
if [[ "${release}" != "${expected_release}" ]]; then
  echo "Kernel release mismatch: got ${release}, expected ${expected_release}" >&2
  exit 1
fi

make -C "${kernel_src}" ARCH=arm CROSS_COMPILE="${cross_compile}" \
  LOCALVERSION="${localversion}" HOSTCFLAGS=-fcommon \
  M="${h6_dir}/driver" modules
mkdir -p "${h6_dir}/build"
cp "${h6_dir}/driver/snitch_job.ko" "${h6_dir}/build/snitch_job.ko"
modinfo "${h6_dir}/build/snitch_job.ko" | sed -n '1,40p'

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S14_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)

BOARD_KERNEL="${BOARD_KERNEL:-console}"

case "${BOARD_KERNEL}" in
  console)
    DEFAULT_KERNEL_SRC="/home/ftv/builds/kernel-src/linux-socfpga-criticallink"
    DEFAULT_LOCALVERSION="-00307-g507abb4-dirty"
    DEFAULT_EXPECTED_RELEASE="3.12.0-00307-g507abb4-dirty"
    ;;
  lxde)
    DEFAULT_KERNEL_SRC="/home/ftv/builds/kernel-src/linux-socfpga-altera-4.5"
    DEFAULT_LOCALVERSION="-00183-g4647b69-dirty"
    DEFAULT_EXPECTED_RELEASE="4.5.0-00183-g4647b69-dirty"
    ;;
  *)
    echo "Unknown BOARD_KERNEL=${BOARD_KERNEL}; use console or lxde" >&2
    exit 1
    ;;
esac

KERNEL_SRC="${KERNEL_SRC:-${DEFAULT_KERNEL_SRC}}"
TOOLCHAIN="${TOOLCHAIN:-/home/ftv/builds/toolchains/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf}"
CROSS_COMPILE="${CROSS_COMPILE:-${TOOLCHAIN}/bin/arm-linux-gnueabihf-}"
LOCALVERSION="${LOCALVERSION:-${DEFAULT_LOCALVERSION}}"
EXPECTED_RELEASE="${EXPECTED_RELEASE:-${DEFAULT_EXPECTED_RELEASE}}"

if [[ ! -d "${KERNEL_SRC}" ]]; then
  echo "Missing KERNEL_SRC=${KERNEL_SRC}" >&2
  exit 1
fi

if [[ ! -x "${CROSS_COMPILE}gcc" ]]; then
  echo "Missing cross compiler: ${CROSS_COMPILE}gcc" >&2
  exit 1
fi

release=$(make -s -C "${KERNEL_SRC}" \
  ARCH=arm \
  CROSS_COMPILE="${CROSS_COMPILE}" \
  LOCALVERSION="${LOCALVERSION}" \
  HOSTCFLAGS=-fcommon \
  kernelrelease)

if [[ "${release}" != "${EXPECTED_RELEASE}" ]]; then
  echo "Kernel release mismatch: got ${release}, expected ${EXPECTED_RELEASE}" >&2
  echo "Run modules_prepare for the board kernel config first." >&2
  exit 1
fi

make -C "${KERNEL_SRC}" \
  ARCH=arm \
  CROSS_COMPILE="${CROSS_COMPILE}" \
  LOCALVERSION="${LOCALVERSION}" \
  HOSTCFLAGS=-fcommon \
  M="${S14_DIR}/driver" \
  modules

mkdir -p "${S14_DIR}/build"
cp "${S14_DIR}/driver/snitch_lite_irq.ko" "${S14_DIR}/build/snitch_lite_irq.ko"
modinfo "${S14_DIR}/build/snitch_lite_irq.ko" | sed -n '1,40p'

#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

OUT_DIR="${S1_DIR}/build"
ELF="${OUT_DIR}/mmio.elf"
MAP="${OUT_DIR}/mmio.map"
DUMP="${OUT_DIR}/mmio.dump"
SRC="${S1_DIR}/sw/mmio.S"
LINKER="${SNITCH_TARGET}/generated/link.ld"
LOCAL_LINKER="${OUT_DIR}/link.ld"

make -C "${SNITCH_TARGET}" \
    CFG_OVERRIDE="${SNITCH_CFG}" \
    "${LINKER}"

mkdir -p "${OUT_DIR}"
sed 's/(rwxai)/(rwx)/' "${LINKER}" > "${LOCAL_LINKER}"

"${SNITCH_LLVM_BIN}/riscv32-unknown-elf-clang" \
    -march=rv32imafd \
    -mabi=ilp32d \
    -mcmodel=medany \
    -nostdlib \
    -fuse-ld="${SNITCH_LLVM_BIN}/ld.lld" \
    -Wl,-T,"${LOCAL_LINKER}" \
    -Wl,-Map,"${MAP}" \
    "${SRC}" \
    -o "${ELF}"

"${SNITCH_LLVM_BIN}/llvm-objdump" -d "${ELF}" > "${DUMP}"

echo "Built ${ELF}"
echo "Wrote ${DUMP}"

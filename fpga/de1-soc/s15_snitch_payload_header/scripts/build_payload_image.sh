#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S15_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)

RISCV_PREFIX="${RISCV_PREFIX:-riscv64-unknown-elf}"
if ! command -v "${RISCV_PREFIX}-gcc" >/dev/null 2>&1; then
    if command -v riscv64-elf-gcc >/dev/null 2>&1; then
        RISCV_PREFIX="riscv64-elf"
    else
        echo "Could not find ${RISCV_PREFIX}-gcc or riscv64-elf-gcc" >&2
        exit 1
    fi
fi

for tool in gcc objcopy objdump nm; do
    if ! command -v "${RISCV_PREFIX}-${tool}" >/dev/null 2>&1; then
        echo "Could not find ${RISCV_PREFIX}-${tool}" >&2
        exit 1
    fi
done

SRC="${S15_PAYLOAD_SRC:-${S15_DIR}/sw/payload_sum.S}"
MAX_WORDS="${S15_PAYLOAD_MAX_WORDS:-16}"
ARG0="${S15_ARG0:-0x00000300}"
ARG1="${S15_ARG1:-0x00000077}"
BUILD_DIR="${S15_DIR}/generated/sw"
LINKER="${BUILD_DIR}/link.ld"
ELF="${BUILD_DIR}/s15_payload.elf"
MAP="${BUILD_DIR}/s15_payload.map"
DUMP="${BUILD_DIR}/s15_payload.dump"
RAW_BIN="${BUILD_DIR}/s15_payload.raw.bin"
IMAGE="${BUILD_DIR}/s15_payload.img"
NM="${BUILD_DIR}/s15_payload.nm"
MANIFEST="${BUILD_DIR}/s15_payload_manifest.json"

if [[ ! -f "${SRC}" ]]; then
    echo "Missing S15_PAYLOAD_SRC=${SRC}" >&2
    exit 1
fi

mkdir -p "${BUILD_DIR}"

cat > "${LINKER}" <<'EOF'
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS {
  . = 0x00000000;
  .text : {
    *(.text.init)
    *(.text*)
  }
}
EOF

"${RISCV_PREFIX}-gcc" \
    -march=rv32e \
    -mabi=ilp32e \
    -mcmodel=medany \
    -nostdlib \
    -nostartfiles \
    -Wl,-T,"${LINKER}" \
    -Wl,-Map,"${MAP}" \
    "${SRC}" \
    -o "${ELF}"

"${RISCV_PREFIX}-nm" -n "${ELF}" > "${NM}"
start_addr=$(awk '$3 == "_start" { print $1; exit }' "${NM}")
if [[ "${start_addr}" != "00000000" ]]; then
    echo "Expected _start at 00000000, got ${start_addr:-missing}" >&2
    echo "NM: ${NM}" >&2
    exit 1
fi

"${RISCV_PREFIX}-objdump" -d "${ELF}" > "${DUMP}"
"${RISCV_PREFIX}-objcopy" -O binary -j .text "${ELF}" "${RAW_BIN}"

python3 "${SCRIPT_DIR}/build_payload_image.py" \
    --raw-bin "${RAW_BIN}" \
    --image "${IMAGE}" \
    --manifest "${MANIFEST}" \
    --source "${SRC}" \
    --dump "${DUMP}" \
    --max-words "${MAX_WORDS}" \
    --arg0 "${ARG0}" \
    --arg1 "${ARG1}"

echo "Built ${ELF}"
echo "Wrote ${DUMP}"
echo "Wrote ${RAW_BIN}"
echo "Wrote ${IMAGE}"
echo "Wrote ${MANIFEST}"

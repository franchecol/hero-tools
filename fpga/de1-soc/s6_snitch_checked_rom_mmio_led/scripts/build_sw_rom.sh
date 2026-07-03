#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

SRC="${S6_SW_SRC}"
LINKER="${SW_BUILD_DIR}/link.ld"
ELF="${SW_BUILD_DIR}/payload.elf"
MAP="${SW_BUILD_DIR}/payload.map"
DUMP="${SW_BUILD_DIR}/payload.dump"
BIN="${SW_BUILD_DIR}/payload.bin"
NM="${SW_BUILD_DIR}/payload.nm"
ROM_SVH="${GENERATED_DIR}/rom_words.svh"
MANIFEST="${GENERATED_DIR}/rom_manifest.json"

if [[ ! -f "${SRC}" ]]; then
    echo "Missing S6_SW_SRC=${SRC}" >&2
    exit 1
fi

mkdir -p "${SW_BUILD_DIR}"

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

start_addr=$(
    awk '$3 == "_start" { print $1; exit }' "${NM}"
)

if [[ "${start_addr}" != "00000000" ]]; then
    echo "Expected _start at 00000000, got ${start_addr:-missing}" >&2
    echo "NM: ${NM}" >&2
    exit 1
fi

"${RISCV_PREFIX}-objdump" -d "${ELF}" > "${DUMP}"
"${RISCV_PREFIX}-objcopy" -O binary -j .text "${ELF}" "${BIN}"

python3 "${S6_DIR}/scripts/bin_to_rom_svh.py" \
    "${BIN}" \
    "${ROM_SVH}" \
    --manifest "${MANIFEST}" \
    --source "${SRC}" \
    --dump "${DUMP}" \
    --max-words "${S6_ROM_MAX_WORDS}" \
    --prefix s6 \
    --default-word 0x0000006f

echo "Built ${ELF}"
echo "Wrote ${DUMP}"
echo "Wrote ${BIN}"
echo "Wrote ${ROM_SVH}"
echo "Wrote ${MANIFEST}"

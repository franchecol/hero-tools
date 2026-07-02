#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

SRC="${S5_DIR}/sw/led_mmio.S"
LINKER="${SW_BUILD_DIR}/link.ld"
ELF="${SW_BUILD_DIR}/led_mmio.elf"
MAP="${SW_BUILD_DIR}/led_mmio.map"
DUMP="${SW_BUILD_DIR}/led_mmio.dump"
BIN="${SW_BUILD_DIR}/led_mmio.bin"
ROM_SVH="${GENERATED_DIR}/rom_words.svh"

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

"${RISCV_PREFIX}-objdump" -d "${ELF}" > "${DUMP}"
"${RISCV_PREFIX}-objcopy" -O binary -j .text "${ELF}" "${BIN}"

python3 "${S5_DIR}/scripts/bin_to_rom_svh.py" \
    "${BIN}" \
    "${ROM_SVH}" \
    --default-word 0x0000006f

echo "Built ${ELF}"
echo "Wrote ${DUMP}"
echo "Wrote ${BIN}"
echo "Wrote ${ROM_SVH}"

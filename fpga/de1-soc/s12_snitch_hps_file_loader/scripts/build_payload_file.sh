#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S12_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
GENERATED_DIR="${S12_DIR}/generated"
SW_BUILD_DIR="${GENERATED_DIR}/sw"
SRC="${S12_PAYLOAD_SRC:-${S12_DIR}/sw/payload_sum.S}"
MAX_WORDS="${S12_PAYLOAD_MAX_WORDS:-16}"
RISCV_PREFIX="${RISCV_PREFIX:-riscv64-unknown-elf}"

if ! command -v "${RISCV_PREFIX}-gcc" >/dev/null 2>&1; then
    if command -v riscv64-elf-gcc >/dev/null 2>&1; then
        RISCV_PREFIX="riscv64-elf"
    else
        echo "Could not find ${RISCV_PREFIX}-gcc or riscv64-elf-gcc" >&2
        exit 1
    fi
fi

for tool in gcc objcopy objdump nm size; do
    if ! command -v "${RISCV_PREFIX}-${tool}" >/dev/null 2>&1; then
        echo "Could not find ${RISCV_PREFIX}-${tool}" >&2
        exit 1
    fi
done

if [[ ! -f "${SRC}" ]]; then
    echo "Missing S12_PAYLOAD_SRC=${SRC}" >&2
    exit 1
fi

mkdir -p "${SW_BUILD_DIR}"

LINKER="${SW_BUILD_DIR}/link.ld"
ELF="${SW_BUILD_DIR}/s12_payload.elf"
MAP="${SW_BUILD_DIR}/s12_payload.map"
DUMP="${SW_BUILD_DIR}/s12_payload.dump"
BIN="${SW_BUILD_DIR}/s12_payload.bin"
NM="${SW_BUILD_DIR}/s12_payload.nm"
MANIFEST="${SW_BUILD_DIR}/payload_manifest.txt"

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

byte_count=$(wc -c < "${BIN}")
if (( byte_count == 0 )); then
    echo "Payload binary is empty: ${BIN}" >&2
    exit 1
fi
if (( byte_count % 4 != 0 )); then
    echo "Payload byte count must be word-aligned, got ${byte_count}" >&2
    exit 1
fi

word_count=$(( byte_count / 4 ))
if (( word_count > MAX_WORDS )); then
    echo "Payload has ${word_count} words, max is ${MAX_WORDS}" >&2
    exit 1
fi

sha256=$(sha256sum "${BIN}" | awk '{ print $1 }')

cat > "${MANIFEST}" <<EOF
source=${SRC}
elf=${ELF}
binary=${BIN}
dump=${DUMP}
byte_count=${byte_count}
word_count=${word_count}
max_words=${MAX_WORDS}
sha256=${sha256}
EOF

echo "Built ${ELF}"
echo "Wrote ${DUMP}"
echo "Wrote ${BIN}"
echo "Payload words: ${word_count}/${MAX_WORDS}"
echo "Wrote ${MANIFEST}"

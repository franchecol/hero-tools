#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S14_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)

mkdir -p "${S14_DIR}/build"

clang \
  --target=armv7a-linux-gnueabihf \
  -fuse-ld=lld \
  -nostdlib \
  -static \
  -nostartfiles \
  -fno-builtin \
  -fno-stack-protector \
  -O2 \
  -Wl,-e,_start \
  -Wl,--build-id=none \
  "${S14_DIR}/sw/s14_irq_wait_nolibc.c" \
  -o "${S14_DIR}/build/s14_irq_wait_nolibc"

file "${S14_DIR}/build/s14_irq_wait_nolibc"


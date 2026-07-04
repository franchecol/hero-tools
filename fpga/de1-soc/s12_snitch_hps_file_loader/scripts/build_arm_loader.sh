#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S12_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)

mkdir -p "${S12_DIR}/build"

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
  "${S12_DIR}/sw/s12_file_loader_nolibc.c" \
  -o "${S12_DIR}/build/s12_file_loader_nolibc"

file "${S12_DIR}/build/s12_file_loader_nolibc"

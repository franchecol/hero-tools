#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p build

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
  sw/s10_mmio_nolibc.c \
  -o build/s10_mmio_nolibc

file build/s10_mmio_nolibc

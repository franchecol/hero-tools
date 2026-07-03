#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

mkdir -p build

clang \
  --target=armv7a-linux-gnueabihf \
  -fuse-ld=lld \
  -nostdlib \
  -static \
  -fno-builtin \
  -fno-stack-protector \
  -O2 \
  -Wl,-e,_start \
  -Wl,--build-id=none \
  sw/d3_mmio_nolibc.c \
  -o build/d3_mmio_nolibc

file build/d3_mmio_nolibc

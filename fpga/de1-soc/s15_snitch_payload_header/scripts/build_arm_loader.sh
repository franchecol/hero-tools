#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build_payload_image.sh

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
  sw/s15_header_loader_nolibc.c \
  -o build/s15_header_loader_nolibc

file build/s15_header_loader_nolibc

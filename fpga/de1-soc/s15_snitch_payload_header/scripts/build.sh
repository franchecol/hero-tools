#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
./scripts/build_arm_loader.sh

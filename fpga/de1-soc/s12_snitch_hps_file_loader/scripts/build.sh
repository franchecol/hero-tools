#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

"${SCRIPT_DIR}/build_payload_file.sh"
"${SCRIPT_DIR}/build_arm_loader.sh"

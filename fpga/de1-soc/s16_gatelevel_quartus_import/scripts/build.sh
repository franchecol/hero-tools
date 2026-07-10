#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f /etc/profile.d/quartus.sh ]; then
    # shellcheck disable=SC1091
    source /etc/profile.d/quartus.sh
fi

quartus_sh --flow compile de1_s16_gatelevel_import

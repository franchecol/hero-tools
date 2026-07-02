#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source /etc/profile.d/quartus.sh

quartus_sh --flow compile de1_d1_register_accel


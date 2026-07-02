#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source /etc/profile.d/quartus.sh

system-console --script=scripts/d2_smoke.tcl


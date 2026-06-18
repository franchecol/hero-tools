#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if [[ "$#" -ne 0 ]]; then
  printf '[occamy-m1-bootstrap] ERROR: M1 takes no mode argument; use environment variables for build options\n' >&2
  exit 1
fi

exec "${SCRIPT_DIR}/bootstrap-local-occamy-minimal.sh" roundtrip

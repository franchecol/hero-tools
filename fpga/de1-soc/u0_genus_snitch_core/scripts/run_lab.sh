#!/usr/bin/env bash
set -euo pipefail

cd "$HOME/snitch_gatelevel_lab/s17"

export LM_LICENSE_FILE=5280@license
export CDS_LIC_FILE=5280@license

/local/tools/GENUS2118/bin/genus \
    -no_gui \
    -legacy_ui \
    -files genus_snitch_core.tcl \
    2>&1 | tee genus_snitch_core.log

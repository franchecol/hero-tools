#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source /etc/profile.d/quartus.sh

qsys-script \
  --search-path="$PWD/ip/d2_mmio_regs,$" \
  --script=scripts/create_qsys.tcl

qsys-generate d2_mmio_system.qsys \
  --synthesis=VERILOG \
  --search-path="$PWD/ip/d2_mmio_regs,$" \
  --family="Cyclone V" \
  --part=5CSEMA5F31C6

quartus_sh --flow compile de1_d2_jtag_mmio_accel

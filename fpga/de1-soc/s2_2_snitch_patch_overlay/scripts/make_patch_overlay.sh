#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

mkdir -p \
    "${PATCH_DIR}/tech_cells_generic/src/rtl" \
    "${PATCH_DIR}/snitch_cluster/src" \
    "${PATCH_DIR}/snitch_icache/src"

cp "${TECH_CELLS_ROOT}/src/rtl/tc_sram.sv" \
    "${PATCH_DIR}/tech_cells_generic/src/rtl/tc_sram.sv"
cp "${TECH_CELLS_ROOT}/src/rtl/tc_sram_impl.sv" \
    "${PATCH_DIR}/tech_cells_generic/src/rtl/tc_sram_impl.sv"
cp "${SNITCH_ROOT}/hw/snitch_cluster/src/snitch_cluster.sv" \
    "${PATCH_DIR}/snitch_cluster/src/snitch_cluster.sv"
cp "${SNITCH_ROOT}/hw/snitch_icache/src/snitch_icache_lookup.sv" \
    "${PATCH_DIR}/snitch_icache/src/snitch_icache_lookup.sv"

TC_SRAM_PATCH="${PATCH_DIR}/tech_cells_generic/src/rtl/tc_sram.sv"
TC_SRAM_IMPL_PATCH="${PATCH_DIR}/tech_cells_generic/src/rtl/tc_sram_impl.sv"
SNITCH_CLUSTER_PATCH="${PATCH_DIR}/snitch_cluster/src/snitch_cluster.sv"
SNITCH_ICACHE_PATCH="${PATCH_DIR}/snitch_icache/src/snitch_icache_lookup.sv"

perl -0pi -e '
    s/(parameter int unsigned BeWidth\s*=[^\n]*),\s*\/\/ ceil_div\n  parameter type\s+addr_t\s*=\s*logic \[AddrWidth-1:0\],\n  parameter type\s+data_t\s*=\s*logic \[DataWidth-1:0\],\n  parameter type\s+be_t\s*=\s*logic \[BeWidth-1:0\]/$1  \/\/ ceil_div/g;
    s/input  addr_t \[NumPorts-1:0\] addr_i/input  logic [NumPorts-1:0][AddrWidth-1:0] addr_i/g;
    s/input  data_t \[NumPorts-1:0\] wdata_i/input  logic [NumPorts-1:0][DataWidth-1:0] wdata_i/g;
    s/input  be_t   \[NumPorts-1:0\] be_i/input  logic [NumPorts-1:0][BeWidth-1:0] be_i/g;
    s/output data_t \[NumPorts-1:0\] rdata_o/output logic [NumPorts-1:0][DataWidth-1:0] rdata_o/g;
    s/\bdata_t sram \[NumWords-1:0\]/logic [DataWidth-1:0] sram [NumWords-1:0]/g;
    s/\baddr_t \[NumPorts-1:0\] r_addr_q/logic [NumPorts-1:0][AddrWidth-1:0] r_addr_q/g;
    s/function automatic data_t random_init_word\(\)/function automatic logic [DataWidth-1:0] random_init_word()/g;
    s/data_t'\''\(\$urandom\(\)\)/\$urandom()/g;
    s/\bdata_t init_val\[NumWords-1:0\]/logic [DataWidth-1:0] init_val [NumWords-1:0]/g;
    s/\bdata_t \[NumPorts-1:0\]\[Latency-1:0\] rdata_q,\s*rdata_d/logic [NumPorts-1:0][Latency-1:0][DataWidth-1:0] rdata_q, rdata_d/g;
' "${TC_SRAM_PATCH}"

perl -0pi -e '
    s/(parameter\s+ImplKey\s*=[^\n]*),\s*\/\/ Reference to specific implementation\n  parameter type\s+impl_in_t\s*=[^\n]*\n  parameter type\s+impl_out_t\s*=[^\n]*\n  parameter\s+\S+\s+ImplOutSim\s*=[^\n]*/$1,     \/\/ Reference to specific implementation\n  parameter              ImplOutSim   = 1'\''b0,    \/\/ Implementation output in synthesis patch/g;
    s/(parameter int unsigned BeWidth\s*=[^\n]*),\s*\/\/ ceil_div\n  parameter type\s+addr_t\s*=\s*logic \[AddrWidth-1:0\],\n  parameter type\s+data_t\s*=\s*logic \[DataWidth-1:0\],\n  parameter type\s+be_t\s*=\s*logic \[BeWidth-1:0\]/$1  \/\/ ceil_div/g;
    s/input  impl_in_t             impl_i/input  logic                 impl_i/g;
    s/output impl_out_t            impl_o/output logic                 impl_o/g;
    s/input  addr_t \[NumPorts-1:0\] addr_i/input  logic [NumPorts-1:0][AddrWidth-1:0] addr_i/g;
    s/input  data_t \[NumPorts-1:0\] wdata_i/input  logic [NumPorts-1:0][DataWidth-1:0] wdata_i/g;
    s/input  be_t   \[NumPorts-1:0\] be_i/input  logic [NumPorts-1:0][BeWidth-1:0] be_i/g;
    s/output data_t \[NumPorts-1:0\] rdata_o/output logic [NumPorts-1:0][DataWidth-1:0] rdata_o/g;
' "${TC_SRAM_IMPL_PATCH}"

perl -0pi -e '
    s/(\.Latency\s*\(\s*1\s*\)),\n\s*\.impl_in_t\s*\([^)]*\)/$1/g;
    s/\.impl_i\s*\([^)]*\)/.impl_i (1'\''b0)/g;
' "${SNITCH_CLUSTER_PATCH}" "${SNITCH_ICACHE_PATCH}"

echo "Generated patch overlay under ${PATCH_DIR}"

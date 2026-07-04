// Copyright 2019 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Author: Florian Zaruba <zarubaf@iis.ee.ethz.ch>
// Author: Paul Scheffler <paulsc@iis.ee.ethz.ch>

/// This module wraps `addr_decode_dync` in its naturally-aligned power of two (NAPOT) variant,
/// alleviating the need to set the `Napot` parameter and using more descriptive `rule_t`
/// field names. See the `addr_decode`documentation for details.
module addr_decode_napot #(
  /// Highest index which can happen in a rule.
  parameter int unsigned NoIndices = 32'd0,
  /// Total number of rules.
  parameter int unsigned NoRules   = 32'd0,
  /// Address width inside the rules and to decode.
  parameter int unsigned AddrWidth = 1,
  /// Rule idx field width. Original common_cells users normally use int unsigned.
  parameter int unsigned RuleIdxWidth = 32,
  /// Dependent parameter, do **not** overwite!
  ///
  /// Width of the `idx_o` output port.
  parameter int unsigned IdxWidth  = cf_math_pkg::idx_width(NoIndices)
) (
  /// Address to decode.
  input  logic [AddrWidth-1:0] addr_i,
  /// Address map: rule with the highest array position wins on collision
  input  logic [NoRules-1:0][RuleIdxWidth+2*AddrWidth-1:0] addr_map_i,
  /// Decoded index.
  output logic [IdxWidth-1:0] idx_o,
  /// Decode is valid.
  output logic                dec_valid_o,
  /// Decode is not valid, no matching rule found.
  output logic                dec_error_o,
  /// Enable default port mapping.
  ///
  /// When not used, tie to `0`.
  input  logic                en_default_idx_i,
  /// Default port index.
  ///
  /// When `en_default_idx_i` is `1`, this will be the index when no rule matches.
  ///
  /// When not used, tie to `0`.
  input  logic [IdxWidth-1:0] default_idx_i
);

  typedef logic [AddrWidth-1:0] addr_t;
  typedef logic [IdxWidth-1:0] idx_t;
  typedef struct packed {
    logic [RuleIdxWidth-1:0] idx;
    addr_t base;
    addr_t mask;
  } rule_t;

  rule_t [NoRules-1:0] addr_map;
  assign addr_map = addr_map_i;

  // Rename struct field names to those expected by `addr_decode`
  typedef struct packed {
    logic [RuleIdxWidth-1:0] idx;
    addr_t start_addr;
    addr_t end_addr;
  } rule_range_t;

  rule_range_t [NoRules-1:0] addr_map_range;
  genvar gen_i;
  generate
    for (gen_i = 0; gen_i < NoRules; gen_i++) begin : gen_rule_range
      assign addr_map_range[gen_i].idx        = addr_map[gen_i].idx;
      assign addr_map_range[gen_i].start_addr = addr_map[gen_i].base;
      assign addr_map_range[gen_i].end_addr   = addr_map[gen_i].mask;
    end
  endgenerate

  addr_decode_dync #(
    .NoIndices    ( NoIndices    ) ,
    .NoRules      ( NoRules      ),
    .AddrWidth    ( AddrWidth    ),
    .RuleIdxWidth ( RuleIdxWidth ),
    .Napot        ( 1            ),
    .IdxWidth     ( IdxWidth     )
  ) i_addr_decode_dync (
    .addr_i,
    .addr_map_i ( addr_map_range ),
    .idx_o,
    .dec_valid_o,
    .dec_error_o,
    .en_default_idx_i,
    .default_idx_i,
    .config_ongoing_i ( 1'b0 )
);

endmodule

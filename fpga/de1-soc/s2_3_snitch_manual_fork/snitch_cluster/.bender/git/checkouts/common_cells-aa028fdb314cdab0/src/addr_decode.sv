// Copyright 2019 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Authors:
// - Wolfgang Roenninger <wroennin@ethz.ch>
// - Thomas Benz <tbenz@iis.ee.ethz.ch>

/// Address Decoder: Maps the input address combinatorially to an index.
/// The address map `addr_map_i` is a packed array of rule_t structs.
/// The ranges of any two rules may overlap. If so, the rule at the higher (more significant)
/// position in `addr_map_i` prevails.
///
/// There can be an arbitrary number of address rules. There can be multiple
/// ranges defined for the same index. The start address has to be less than the end address.
///
/// There is the possibility to add a default mapping:
/// `en_default_idx_i`: Driving this port to `1'b1` maps all input addresses
/// for which no rule in `addr_map_i` exists to the default index specified by
/// `default_idx_i`. In this case, `dec_error_o` is always `1'b0`.
///
/// The `Napot` parameter allows using naturally-aligned power of two (NAPOT) regions,
/// using base addresses and masks instead of address ranges to specify rules.
///
/// Assertions: The module checks every time there is a change in the address mapping
/// if the resulting map is valid. It fatals if `start_addr` is higher than `end_addr` (non-NAPOT
/// only) or if a mapping targets an index that is outside the number of allowed indices.
/// It issues warnings if the address regions of any two mappings overlap (non-NAPOT only).
module addr_decode #(
  /// Highest index which can happen in a rule.
  parameter int unsigned NoIndices = 32'd0,
  /// Total number of rules.
  parameter int unsigned NoRules   = 32'd0,
  /// Address width inside the rules and to decode.
  parameter int unsigned AddrWidth = 1,
  /// Rule idx field width. Original common_cells users normally use int unsigned.
  parameter int unsigned RuleIdxWidth = 32,
  // Whether this is a NAPOT (base and mask) or regular range decoder
  parameter bit          Napot     = 0,
  /// The output index type `idx_t` can be specified either with the width `IdxWidth`
  /// or directly with the type `idx_t`. By default, it will use the maximum index
  /// `NoIndices` to calculate the required width.
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
    addr_t start_addr;
    addr_t end_addr;
  } rule_t;

  // wraps the dynamic configuration version of the address decoder
  addr_decode_dync #(
    .NoIndices    ( NoIndices    ),
    .NoRules      ( NoRules      ),
    .AddrWidth    ( AddrWidth    ),
    .RuleIdxWidth ( RuleIdxWidth ),
    .Napot        ( Napot        ),
    .IdxWidth     ( IdxWidth     )
  ) i_addr_decode_dync (
    .addr_i,
    .addr_map_i,
    .idx_o,
    .dec_valid_o,
    .dec_error_o,
    .en_default_idx_i,
    .default_idx_i,
    .config_ongoing_i ( 1'b0 )
  );

endmodule

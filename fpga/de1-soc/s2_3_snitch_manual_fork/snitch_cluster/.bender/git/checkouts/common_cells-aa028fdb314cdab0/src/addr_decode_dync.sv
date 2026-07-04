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
// - Paul Scheffler <paulsc@iis.ee.ethz.ch>
// - Michael Rogenmoser <michaero@iis.ee.ethz.ch>
// - Thomas Benz <tbenz@iis.ee.ethz.ch>

`include "common_cells/assertions.svh"

/// Address Decoder: Maps the input address combinatorially to an index.
/// DYNamic Configuration (DYNC) version
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
module addr_decode_dync #(
  /// Highest index which can happen in a rule.
  parameter int unsigned NoIndices = 32'd0,
  /// Total number of rules.
  parameter int unsigned NoRules   = 32'd0,
  /// Address width inside the rules and to decode.
  parameter int unsigned AddrWidth = 1,
  /// Rule idx field width. Original common_cells users normally use int unsigned.
  parameter int unsigned RuleIdxWidth = 32,
  /// Whether this is a NAPOT (base and mask) or regular range decoder
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
  input  logic [IdxWidth-1:0] default_idx_i,
  /// The module is dynamically configured, this deactivates its output and the integrated
  /// assertions.
  input  logic                config_ongoing_i
);

  typedef logic [AddrWidth-1:0] addr_t;
  typedef logic [IdxWidth-1:0] idx_t;
  typedef struct packed {
    logic [RuleIdxWidth-1:0] idx;
    addr_t start_addr;
    addr_t end_addr;
  } rule_t;

  rule_t [NoRules-1:0] addr_map;
  assign addr_map = addr_map_i;

  logic [NoRules-1:0] matched_rules; // purely for address map debugging

  always_comb begin
    // default assignments
    matched_rules = '0;
    dec_valid_o   = 1'b0;
    dec_error_o   = (en_default_idx_i) ? 1'b0 : 1'b1;
    idx_o         = (en_default_idx_i) ? default_idx_i : '0;

    // match the rules
    for (int unsigned i = 0; i < NoRules; i++) begin
      if (
        !Napot && (addr_i >= addr_map[i].start_addr) &&
        ((addr_i < addr_map[i].end_addr) || (addr_map[i].end_addr == '0)) ||
        Napot && (addr_map[i].start_addr & addr_map[i].end_addr) ==
                 (addr_i & addr_map[i].end_addr)
      ) begin
        matched_rules[i] = ~config_ongoing_i;
        dec_valid_o      = ~config_ongoing_i;
        dec_error_o      = 1'b0;
        idx_o            = config_ongoing_i ? default_idx_i : idx_t'(addr_map[i].idx);
      end
    end
  end

  // Assumptions and assertions
  `ifndef COMMON_CELLS_ASSERTS_OFF
  initial begin : proc_check_parameters
    `ASSUME_I(addr_width_mismatch, $bits(addr_i) == $bits(addr_map[0].start_addr))
    `ASSUME_I(norules_0, NoRules > 0)
  end

  `ASSERT_FINAL(more_than_1_bit_set, $onehot0(matched_rules) || config_ongoing_i)

  // These following assumptions check the validity of the address map.
  // The assumptions gets generated for each distinct pair of rules.
  // Each assumption is present two times, as they rely on one rules being
  // effectively ordered. Only one of the rules with the same function is
  // active at a time for a given pair.
  // check_start:        Enforces a smaller start than end address.
  // check_idx:          Enforces a valid index in the rule.
  // check_overlap:      Warns if there are overlapping address regions.
  `ifndef SYNTHESIS
  always_comb begin : proc_check_addr_map
    if (!$isunknown(addr_map_i) && ~config_ongoing_i) begin
      for (int unsigned i = 0; i < NoRules; i++) begin
        `ASSUME_I(check_start, Napot || addr_map[i].start_addr < addr_map[i].end_addr ||
          addr_map[i].end_addr == '0)
        for (int unsigned j = i + 1; j < NoRules; j++) begin
          // overlap check
          `ASSUME_I(check_overlap, Napot ||
                                  !((addr_map[j].start_addr < addr_map[i].end_addr) &&
                                    (addr_map[j].end_addr > addr_map[i].start_addr)) ||
                                  !((addr_map[i].end_addr == '0) &&
                                    (addr_map[j].end_addr > addr_map[i].start_addr)) ||
                                  !((addr_map[j].start_addr < addr_map[i].end_addr) &&
                                    (addr_map[j].end_addr == '0)))
        end
      end
    end
  end
  `endif
  `endif

endmodule

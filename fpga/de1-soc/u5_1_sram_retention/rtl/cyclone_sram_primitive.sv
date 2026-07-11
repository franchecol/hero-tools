// Cyclone V implementation of the SRAM boundary preserved by Genus.
module cyclone_sram_primitive #(
  parameter int unsigned NumWords  = 512,
  parameter int unsigned DataWidth = 64,
  parameter int unsigned ByteWidth = 8,
  parameter int unsigned AddrWidth = (NumWords > 1) ? $clog2(NumWords) : 1,
  parameter int unsigned BeWidth   = DataWidth / ByteWidth
) (
  input  logic                 clk_i,
  input  logic                 req_i,
  input  logic                 we_i,
  input  logic [AddrWidth-1:0] addr_i,
  input  logic [DataWidth-1:0] wdata_i,
  input  logic [BeWidth-1:0]   be_i,
  output logic [DataWidth-1:0] rdata_o
);
  altsyncram #(
    .operation_mode                 ("SINGLE_PORT"),
    .intended_device_family         ("Cyclone V"),
    .ram_block_type                 ("M10K"),
    .numwords_a                     (NumWords),
    .widthad_a                      (AddrWidth),
    .width_a                        (DataWidth),
    .width_byteena_a                (BeWidth),
    .byte_size                      (ByteWidth),
    .outdata_reg_a                  ("CLOCK0"),
    .clock_enable_input_a           ("NORMAL"),
    .clock_enable_output_a          ("NORMAL"),
    .read_during_write_mode_port_a  ("DONT_CARE"),
    .power_up_uninitialized         ("TRUE"),
    .lpm_type                       ("altsyncram")
  ) i_m10k (
    .clock0         (clk_i),
    .clocken0       (req_i),
    .address_a      (addr_i),
    .data_a         (wdata_i),
    .byteena_a      (be_i),
    .rden_a         (1'b1),
    .wren_a         (we_i),
    .q_a            (rdata_o),
    .aclr0          (1'b0),
    .aclr1          (1'b0),
    .addressstall_a (1'b0),
    .address_b      (1'b1),
    .addressstall_b (1'b0),
    .byteena_b      (1'b1),
    .clock1         (1'b1),
    .clocken1       (1'b1),
    .clocken2       (1'b1),
    .clocken3       (1'b1),
    .data_b         (1'b1),
    .rden_b         (1'b1),
    .wren_b         (1'b0),
    .q_b            (),
    .eccstatus      ()
  );
endmodule

module cyclone_sram_512x64 (
  input logic clk_i, req_i, we_i,
  input logic [8:0] addr_i,
  input logic [63:0] wdata_i,
  input logic [7:0] be_i,
  output logic [63:0] rdata_o
);
  cyclone_sram_primitive #(.NumWords(512), .DataWidth(64)) i_mem (.*);
endmodule

module cyclone_sram_128x128 (
  input logic clk_i, req_i, we_i,
  input logic [6:0] addr_i,
  input logic [127:0] wdata_i,
  input logic [15:0] be_i,
  output logic [127:0] rdata_o
);
  cyclone_sram_primitive #(.NumWords(128), .DataWidth(128)) i_mem (.*);
endmodule

module cyclone_sram_128x24 (
  input logic clk_i, req_i, we_i,
  input logic [6:0] addr_i,
  input logic [23:0] wdata_i,
  input logic [2:0] be_i,
  output logic [23:0] rdata_o
);
  cyclone_sram_primitive #(.NumWords(128), .DataWidth(24)) i_mem (.*);
endmodule

module CKBD0 (
  input  logic I,
  output logic Z
);
  assign Z = I;
endmodule

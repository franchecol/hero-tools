// Fixed-width implementation used after Genus has specialized type parameters.
module cyclone_sram #(
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
  (* ramstyle = "M10K, no_rw_check" *) logic [DataWidth-1:0] mem [0:NumWords-1];

  always_ff @(posedge clk_i) begin
    if (req_i) begin
      if (we_i) begin
        for (int unsigned lane = 0; lane < BeWidth; lane++) begin
          if (be_i[lane]) begin
            mem[addr_i][lane*ByteWidth +: ByteWidth] <=
                wdata_i[lane*ByteWidth +: ByteWidth];
          end
        end
      end else begin
        rdata_o <= mem[addr_i];
      end
    end
  end
endmodule

module cyclone_sram_512x64 (
  input logic clk_i, req_i, we_i,
  input logic [8:0] addr_i,
  input logic [63:0] wdata_i,
  input logic [7:0] be_i,
  output logic [63:0] rdata_o
);
  cyclone_sram #(.NumWords(512), .DataWidth(64)) i_mem (.*);
endmodule

module cyclone_sram_128x128 (
  input logic clk_i, req_i, we_i,
  input logic [6:0] addr_i,
  input logic [127:0] wdata_i,
  input logic [15:0] be_i,
  output logic [127:0] rdata_o
);
  cyclone_sram #(.NumWords(128), .DataWidth(128)) i_mem (.*);
endmodule

module cyclone_sram_128x24 (
  input logic clk_i, req_i, we_i,
  input logic [6:0] addr_i,
  input logic [23:0] wdata_i,
  input logic [2:0] be_i,
  output logic [23:0] rdata_o
);
  cyclone_sram #(.NumWords(128), .DataWidth(24)) i_mem (.*);
endmodule

// Genus inserted six TSMC65 CKBD0 buffers as loop-breaking identity cells.
// Their technology-independent behavior is a non-inverting one-bit buffer.
module CKBD0 (
  input  logic I,
  output logic Z
);
  assign Z = I;
endmodule

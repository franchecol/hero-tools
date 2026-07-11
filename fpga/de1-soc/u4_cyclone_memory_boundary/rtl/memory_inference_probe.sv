module memory_inference_probe (
  input  logic       CLOCK_50,
  input  logic [3:0] KEY,
  output logic [9:0] LEDR
);
  logic [8:0] addr;
  logic [127:0] pattern;
  logic [63:0] tcdm_rdata;
  logic [127:0] ic_data_rdata;
  logic [23:0] ic_tag_rdata;

  always_ff @(posedge CLOCK_50 or negedge KEY[0]) begin
    if (!KEY[0]) begin
      addr <= '0;
      pattern <= 128'h1;
    end else begin
      addr <= addr + 1'b1;
      pattern <= {pattern[126:0], pattern[127] ^ pattern[125] ^ pattern[100] ^ pattern[98]};
    end
  end

  cyclone_sram_512x64 i_tcdm (
    .clk_i (CLOCK_50), .req_i (1'b1), .we_i (KEY[1]), .addr_i (addr),
    .wdata_i (pattern[63:0]), .be_i ('1), .rdata_o (tcdm_rdata)
  );

  cyclone_sram_128x128 i_icache_data (
    .clk_i (CLOCK_50), .req_i (1'b1), .we_i (KEY[1]), .addr_i (addr[6:0]),
    .wdata_i (pattern), .be_i ('1), .rdata_o (ic_data_rdata)
  );

  cyclone_sram_128x24 i_icache_tag (
    .clk_i (CLOCK_50), .req_i (1'b1), .we_i (KEY[1]), .addr_i (addr[6:0]),
    .wdata_i (pattern[87:64]), .be_i ('1), .rdata_o (ic_tag_rdata)
  );

  always_comb begin
    LEDR[2:0] = {^ic_tag_rdata, ^ic_data_rdata, ^tcdm_rdata};
    LEDR[9:3] = addr[8:2];
  end
endmodule

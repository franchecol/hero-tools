`timescale 1ns/1ps

module de1_s18_genus_snitch_rom_mmio_tb;
  logic CLOCK_50;
  logic [0:0] KEY;
  logic [9:0] LEDR;

  de1_s18_genus_snitch_rom_mmio dut (.*);

  initial begin
    CLOCK_50 = 1'b0;
    forever #10 CLOCK_50 = ~CLOCK_50;
  end

  initial begin
    KEY[0] = 1'b0;
    repeat (4) @(posedge CLOCK_50);
    KEY[0] = 1'b1;
    repeat (24) @(posedge CLOCK_50);

    if (LEDR !== 10'h355) begin
      $fatal(1, "FAIL: expected LEDR=0x355, got 0x%03h", LEDR);
    end

    $display("PASS: Genus Snitch ROM program produced LEDR=0x%03h", LEDR);
    $finish;
  end
endmodule

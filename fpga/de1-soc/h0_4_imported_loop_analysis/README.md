# H0.4: Imported Genus Loop Analysis

H0.4 classifies the combinational-loop warning found during H0.3 before any
Linux software starts the upstream cluster.

## Evidence

The warning predates the HPS integration:

```text
U5.2 standalone cluster: one 417-node loop
H0.3 HPS-connected top: one 244-node loop
```

The changed node count comes from constant propagation at the H0.1 boundary.
Both reports point into the same imported AXI conversion logic. The Genus
netlist contains this explicitly named cell:

```text
i_axi_to_reg
  -> i_axi_to_axi_lite
  -> i_axi_burst_splitter
  -> write-channel counters
  -> i_idq_cdn_loop_breaker
```

Relevant implementation locations are:

```text
Imported marker:
  u4_cyclone_memory_boundary/generated/de1_u4_cluster_quartus.v
  instance ...i_idq_cdn_loop_breaker

Quartus compatibility model:
  u4_cyclone_memory_boundary/rtl/cyclone_sram.sv
  module CKBD0, modeled as the identity Z = I

Original upstream path:
  q2_3_snitch_manual_fork/snitch_cluster/hw/snitch_cluster/src/snitch_cluster.sv
  i_axi_to_reg peripheral adapter

  q2_3_snitch_manual_fork/snitch_cluster/.bender/git/checkouts/
  axi-10c18867bc585e38/src/axi_burst_splitter_gran.sv
  write-channel id_queue instance

  q2_3_snitch_manual_fork/snitch_cluster/.bender/git/checkouts/
  common_cells-aa028fdb314cdab0/src/id_queue.sv
  ID-queue grant and simultaneous pop/push logic
```

Genus used six TSMC65 `CKBD0` identity cells, including one named
`cdn_loop_breaker`. This is strong evidence that the ASIC synthesis flow
deliberately selected those arcs as timing-analysis cuts. The original generic
Verilog model preserved the Boolean identity but not the tool-specific cut
metadata, so Quartus discovered the cycle again.

## FPGA Treatment

H0.4 maps every CKBD0 to an Intel `lcell`. Quartus constant propagation removes
one inactive marker and preserves five active identity markers; the DE1 SDC
requires and disables exactly those five timing arcs. It does not insert a
register, change AXI latency, or hide all combinational loops globally. The
experiment passes only if:

```text
exactly five active preserved marker cells are found
Quartus no longer reports a combinational timing loop
15 MHz setup and hold timing remain positive
the full build still emits SOF and RBF artifacts
```

This resolves static timing analysis portability. Runtime behavior still needs
an HPS-side read-only probe followed by a reset-held write/read test before the
cluster is released to execute.

## Result

The verified H0.4 rebuild completed the physical flow:

```text
Preserved active loop markers:  5
Quartus combinational loops:     0
Physical Fitter:                 PASS
Logic utilization:               9,638 / 32,070 ALMs (30%)
Registers:                       7,448
Physical RAM blocks:            24 / 397 M10Ks (6%)
Worst setup slack:              +13.421 ns
Worst hold slack:               +0.129 ns
SOF and RBF:                     generated
```

The remaining unconstrained-path notice belongs to the intentionally omitted
HPS memory interfaces, not the generated 15 MHz cluster clock.

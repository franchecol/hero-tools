# DE1-SoC Experiment Tracks

This guide separates experiments that were previously numbered as if they
formed one linear `S0` through `S19` sequence. They represent different
technical strategies and have different architectural meanings.

## Track Map

```text
D: board foundation
  Quartus/JTAG -> Avalon-MM -> ARM/HPS Linux

Q: direct upstream frontend investigation
  upstream Snitch -> Verilator succeeds -> direct Quartus frontend fails

SL: Snitch-Lite fallback
  translated real core + custom DE1 shell -> payload/RAM/HPS/IRQ proofs

X: external-synthesis bridge
  Genus netlist -> compatibility boundary -> Quartus/Cyclone V

U: preferred upstream path
  original upstream SystemVerilog -> Genus -> generic netlist -> Quartus

H: future heterogeneous path
  ARM/Linux -> upstream-derived Snitch cluster
```

## Architectural Boundary

```text
Snitch-Lite (`SL`)
  Uses a real/translated Snitch core, but replaces the upstream cluster,
  TCDM, interconnect, host contract, and peripherals with a custom DE1 shell.

Upstream (`U`)
  Feeds original upstream SystemVerilog directly to Genus. Board wrappers are
  adaptation boundaries; the goal is to preserve progressively more upstream
  cluster infrastructure instead of recreating it locally.
```

The `SL` track remains valuable evidence: it proves payload loading, host data,
HPS MMIO, completion IRQs, and Linux driver integration on this board. It is no
longer the preferred implementation path because Genus has now demonstrated a
working frontend for the original upstream RTL.

## Historical Rename Map

```text
Old directory                         Current directory
──────────────────────────────────────────────────────────────────────
s0_snitch_verilator                  q0_snitch_verilator
s1_snitch_mmio_trace                 q1_snitch_mmio_trace
s2_snitch_quartus_wrapper            q2_snitch_quartus_wrapper
s2_2_snitch_patch_overlay            q2_2_snitch_patch_overlay
s2_3_snitch_manual_fork              q2_3_snitch_manual_fork
s3_snitch_core_only_probe            sl3_snitch_core_only_probe
s4_snitch_rom_mmio_led               sl4_snitch_rom_mmio_led
s5_snitch_generated_rom_mmio_led     sl5_snitch_generated_rom_mmio_led
s6_snitch_checked_rom_mmio_led       sl6_snitch_checked_rom_mmio_led
s7_snitch_tiny_ram_check             sl7_snitch_tiny_ram_check
s8_snitch_jtag_host_ctrl             sl8_snitch_jtag_host_ctrl
s9_snitch_hps_host_ctrl              sl9_snitch_hps_host_ctrl
s10_snitch_hps_data_input            sl10_snitch_hps_data_input
s11_snitch_hps_payload_loader        sl11_snitch_hps_payload_loader
s12_snitch_hps_file_loader           sl12_snitch_hps_file_loader
s13_snitch_hps_irq_done              sl13_snitch_hps_irq_done
s14_snitch_hps_irq_linux             sl14_snitch_hps_irq_linux
s15_snitch_payload_header            sl15_snitch_payload_header
s16_gatelevel_quartus_import         x0_gatelevel_quartus_import
s17_genus_snitch_core                u0_genus_snitch_core
s18_genus_snitch_rom_mmio            u1_genus_snitch_rom_mmio
s19_genus_snitch_data_ram            u2_genus_snitch_data_ram
```

Legacy internal names such as `de1_s13_*`, `S13_DIR`, payload filenames, Qsys
component names, capture filenames, and remote lab directories remain intact.
They are implementation identifiers and historical evidence, not navigation
labels. Renaming them would add tool-generated churn without changing the
architecture.

## Preferred Roadmap

```text
U0  Original upstream Snitch integer core through Genus          PASS
U1  U0 core executes generated ROM and writes MMIO               PASS
U2  U0 core performs store/load/compare through local RAM        PASS
U3  Smallest upstream one-core snitch_cluster through Genus      PASS
U4  Cyclone memory boundary, TCDM execution, and device fit      NEXT
H0  ARM/Linux loads and controls upstream-derived cluster        deferred
H1  Completion interrupt and Linux blocking wait                 deferred
```

U3 answered the frontend and generic-synthesis feasibility questions without
substituting a custom cluster:

```text
1. Can Genus elaborate the original snitch_cluster hierarchy?
2. Can it synthesize a meaningful one-core generic netlist?
3. Which upstream modules and parameters dominate area?
4. Can Quartus import and fit that netlist on Cyclone V? U4
5. Can software execute against the upstream TCDM path? U4
```

U4 must not import the 415,192-instance generic netlist as if it were a useful
FPGA implementation. Most of that size comes from ASIC-style SRAM models being
expanded into logic. Preserve the upstream TCDM and I-cache interfaces, add a
Cyclone V memory implementation boundary, then synthesize and measure fit.

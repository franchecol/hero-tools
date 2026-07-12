# H0.2: HPS Avalon to Upstream AXI Bridge

H0.2 replaces the Snitch-Lite-specific SL9 register block with a protocol
adapter for the real upstream cluster host interface.

```text
ARM Cortex-A9 Linux
        │ 32-bit lightweight HPS-to-FPGA Avalon-MM
        ▼
single-beat Avalon-to-AXI adapter
        │ 64-bit AXI, 32-bit transfer size and byte strobes
        ▼
H0.1 stable narrow_in AXI shell
        │
        ▼
upstream Snitch cluster TCDM/peripherals
```

The adapter serializes one Avalon transaction at a time. It supports
independent AXI write-address and write-data handshakes, waits for AXI read or
write responses, maps lower/upper 32-bit Avalon words into the correct 64-bit
AXI byte lanes, and adds the cluster base address `0x10000000`.

## Adapter Test

```bash
./scripts/test_adapter.sh
```

The test deliberately accepts AXI write address and data on different cycles,
then checks lower and upper 32-bit reads. This catches the handshake and lane
mapping errors most likely to corrupt a payload loader.

## Qsys Integration

Package the adapter plus H0.1 shell as a Qsys component and connect it to the
proven SL9 lightweight HPS bridge:

```bash
./scripts/generate_qsys.sh
```

The exported Qsys clock is declared as 20 MHz. The future board top must
generate that clock from `CLOCK_50`; it must not connect the 50 MHz oscillator
directly while claiming a 20 MHz constraint. This Qsys build is an integration
and HDL-generation gate. Physical board execution and payload loading belong
to the following milestone.

## Verified Result

```text
Verilator adapter assertions:       PASS
Split AXI AW/W handshakes:          PASS
Lower 32-bit write lane:            PASS
Lower and upper 32-bit read lanes:  PASS
Qsys validation:                    PASS
HPS AXI-to-Avalon interconnect:     GENERATED
Avalon-to-upstream-AXI component:   GENERATED
Generated synthesis system:         21 modules / 80 files
```

Platform Designer inserted interconnect between the HPS
`h2f_lw_axi_master` and `upstream_cluster.s1`, then generated the complete
synthesis HDL successfully. The warnings about unavailable HPS bridge
simulation and unused HPS I/O/DDR settings are inherited from the proven
bridge-only SL9 configuration; they do not invalidate generation.

The current address translation is:

```text
ARM physical 0xff200000 + local offset
                │
                ▼
Qsys lightweight bridge offset
                │
                ▼
upstream AXI 0x10000000 + local offset
```

H0.3 must supply the declared 20 MHz clock from the board's 50 MHz oscillator,
add the physical DE1 top-level wrapper, and run the complete Quartus flow.

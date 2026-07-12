# H0.7: Observable Upstream Boot

H0.7 replaces the H0.6 infinite-loop placeholder with a real RV32 program and
connects the upstream cluster's narrow data AXI master to a small signature
target. It proves instruction execution and a data-side transaction, not only
instruction fetch.

```text
ARM Linux
  │ release reset / read status and result
  ▼
safe_host_control
  │
  ├── wide_out AXI ──► boot ROM at 0x00001000
  │                     lui / li / sw / loop
  │
  └── narrow_out AXI ► signature sink at 0x00002000
                        captures 0x000005a5
```

## Firmware

[`firmware/boot_store.S`](firmware/boot_store.S) builds as RV32IMA/ILP32 at
`0x1000`. It stores `0x5a5` to `0x2000` and then stops itself in a local loop.

```text
Address    Instruction  Meaning
────────────────────────────────────────────────────
0x1000     000022b7     t0 = 0x2000
0x1004     5a500313     t1 = 0x5a5
0x1008     0062a023     store t1 through data AXI
0x100c     0000006f     remain in a safe loop
```

The build script checks both the 16-byte size and the exact four generated
words. The H0.6 ROM currently embeds these checked words.

```bash
./scripts/build_firmware.sh
./scripts/test_signature_sink.sh
```

The sink test covers independent AW/W arrival, write-response backpressure,
the two 32-bit lanes of the 64-bit AXI bus, byte strobes, sticky result state,
reset clearing, and DECERR for unsupported writes.

## Integration

The instruction path remains attached to `wide_out`; the signature sink is
attached to `narrow_out`, which is the upstream Snitch core-data path. H0.7
therefore activates the sixth Genus loop-cut marker. The Quartus SDC checks
that exactly six markers exist before disabling timing through those explicit
netlist loop-breaker cells.

```text
Quartus fit:             PASS
Logic utilization:      10,545 / 32,070 ALMs (33%)
Registers:              7,631
M10K blocks:            24 / 397 (6%)
Worst setup slack:      +17.568 ns
Worst hold slack:       +0.127 ns
Combinational loops:    0
SOF and RBF:            generated
```

## Register Result

The H0.5 local page exposes the H0.7 observation without forwarding an ARM
transaction into the cluster:

```text
0xff200004  CONTROL      bit 0 releases cluster reset
0xff200008  STATUS       bit 3 fetch seen, bit 4 result valid
0xff200010  BOOT_RESULT  captured 32-bit data-side store
```

## Physical Result

Verified on the DE1-SoC from ARM Linux over the lightweight HPS bridge on
2026-07-12:

```text
INITIAL_STATUS   = 0x00000005
INITIAL_RESULT   = 0x00000000
RELEASED_STATUS  = 0x0000001e
RELEASED_RESULT  = 0x000005a5
HELD_STATUS      = 0x00000005
HELD_RESULT      = 0x00000000
```

`STATUS=0x1e` means reset released, PLL locked, instruction fetch observed,
and result observed. The exact `0x5a5` result proves that the real upstream
Snitch executed the boot payload and completed its store through the narrow
data AXI path. Reasserting reset clears both sticky observations and leaves the
cluster safe.

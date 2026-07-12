# H0.6: External AXI Boot ROM

The upstream cluster is synthesized with `BootAddr=0x00001000`, outside its
TCDM at `0x10000000`. H0.6 preserves that upstream architecture and replaces
the H0.1 error tie-off on the instruction cache's `wide_out` master with an
external 64-bit AXI boot ROM. The core-data path uses `narrow_out`; the first
physical integration attempt attached there and correctly produced no fetch.

The first slice implements and verifies the target independently:

```text
Snitch instruction request
  -> wide_out AXI AR burst
  -> ROM at 0x00001000
  -> AXI R beats with original ID and RLAST
```

The original H0.6 placeholder image contained `jal x0, 0` (`0x0000006f`) so
releasing the cluster could not escape the ROM or touch an unimplemented
external address. H0.7 later replaced the ROM contents with an observable
four-instruction payload while preserving this AXI target.

```bash
./scripts/test_boot_rom.sh
```

The test covers a two-beat 64-bit INCR burst, response backpressure, stable
data/ID/last signals, the sticky boot-fetch observation, and DECERR outside the
ROM window. Integration into the gate-level shell follows only after this
protocol boundary passes.

## H0.6.2 Physical Integration

The ROM is connected to the gate-level cluster's `wide_out` instruction-cache
master. A first physical experiment connected it to `narrow_out`; releasing
reset produced `STATUS=0x6` with no fetch. Source tracing then confirmed that
`snitch_hive` connects the I-cache refill port to `wide_axi_mst_req[ICache]`.

The corrected wide-port design completes the physical flow:

```text
Quartus fit:             PASS
Logic utilization:      9,935 / 32,070 ALMs (31%)
Registers:              7,464
M10K blocks:            24 / 397 (6%)
Worst setup slack:      +17.406 ns
Worst hold slack:       +0.122 ns
Combinational loops:    0
SOF and RBF:            generated
```

## H0.6.3 Board Result

After a clean restart and immediate LXDE headless preparation, the corrected
wide-port bitstream remained accessible from ARM Linux. A controlled release,
one-second observation, and immediate reset reassertion produced:

```text
INITIAL_STATUS  = 0x00000005  held + PLL locked
RELEASED_STATUS = 0x0000000e  released + PLL locked + boot fetch seen
HELD_STATUS     = 0x00000005  held again; fetch observation reset
```

This proves that the real gate-level Snitch instruction cache issued an AXI
request after reset release and completed a boot-window address handshake with
the H0.6 ROM on `wide_out`. The placeholder instruction keeps execution in a
safe infinite loop at `0x1000`; no useful payload has run yet.

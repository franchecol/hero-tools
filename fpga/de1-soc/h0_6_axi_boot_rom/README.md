# H0.6: External AXI Boot ROM

The upstream cluster is synthesized with `BootAddr=0x00001000`, outside its
TCDM at `0x10000000`. H0.6 preserves that upstream architecture and replaces
the H0.1 error tie-off on the cluster's `narrow_out` master with an external
64-bit AXI boot ROM.

The first slice implements and verifies the target independently:

```text
Snitch instruction request
  -> narrow_out AXI AR burst
  -> ROM at 0x00001000
  -> AXI R beats with original ID and RLAST
```

The placeholder image contains `jal x0, 0` (`0x0000006f`) so releasing the
cluster cannot escape the ROM or touch an unimplemented external address.

```bash
./scripts/test_boot_rom.sh
```

The test covers a two-beat 64-bit INCR burst, response backpressure, stable
data/ID/last signals, the sticky boot-fetch observation, and DECERR outside the
ROM window. Integration into the gate-level shell follows only after this
protocol boundary passes.

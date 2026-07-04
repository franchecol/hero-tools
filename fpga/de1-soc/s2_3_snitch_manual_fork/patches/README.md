# S2.3 Manual Patch Diffs

This folder records line-level diffs between the original Snitch checkout used
by Occamy and the manually edited S2.3 fork.

These files exist because the S2.3 fork was imported into `hero-tools` after
the first manual edits. In a normal Git commit view, many S2.3 source files look
like whole-file additions because Git had no previous committed version of those
files inside `fpga/de1-soc/s2_3_snitch_manual_fork/`.

Use these patch files when you want the useful view:

```text
original Occamy/Bender Snitch source
vs.
S2.3 manually edited Snitch source
```

Current patches:

```text
attempt1_sram_type_parameter_port.patch
  Documents the first manual S2.3 change:
  remove Quartus-incompatible SRAM type parameters and update call sites.
```

To regenerate the same style of comparison manually:

```bash
cd /home/ftv/builds/hero-tools

orig=platforms/occamy/.bender/git/checkouts/snitch_cluster-85bc3373558d290b
fork=fpga/de1-soc/s2_3_snitch_manual_fork/snitch_cluster

diff -u \
  --label "original/<relative-path>" \
  --label "s2_3/<relative-path>" \
  "$orig/<relative-path>" \
  "$fork/<relative-path>"
```


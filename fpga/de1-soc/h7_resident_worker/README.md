# H7: Resident Snitch Worker and Job Doorbell

H7 keeps the Snitch worker running across job submissions. Linux and Snitch
still alternate ownership of shared memory, but reset is no longer the
per-job ownership boundary. A hardware doorbell transfers ownership to the
resident worker; its completion store transfers ownership back to Linux.

```text
ARM Linux / driver              FPGA ownership               Resident Snitch
       │                               │                            │
       ├─ upload worker once ─────────►│ boot M10K                  │
       ├─ release reset once           │───────────────────────────►│ poll 0x3000
       │                               │                            │
       ├─ write job 0                  │ host owns shared M10K      │
       ├─ ring doorbell ──────────────►│ Snitch owns shared M10K ──►│ compute
       │◄──────────── IRQ/completion ──│ host owns shared M10K ◄────┤
       ├─ write job 1                  │                            │ poll, no reset
       ├─ ring doorbell ──────────────►│ Snitch owns shared M10K ──►│ compute
       │◄──────────── IRQ/completion ──│ host owns shared M10K ◄────┤
       └─ write/ring job 2             │                            │ same worker
```

The physical proof reports `WORKER_STARTS=1` for all three jobs. Correct
arithmetic alone would not prove residency because H5/H6 already produced the
same outputs by resetting Snitch between jobs.

## Hardware Contract

H7 adds one host control register and one Snitch-visible address:

```text
ARM physical address  Local word  Meaning
0xff20002c            11          JOB_DOORBELL / ownership status

JOB_DOORBELL read bits
bit 0   job active; shared memory belongs to Snitch
bit 1   resident mode has been entered
bit 2   host may access shared memory

JOB_DOORBELL write
bit 0 = 1   acknowledge the previous completion and transfer ownership
            to the resident Snitch worker

Snitch address
0x00003000  returns job-active in bit 0
```

The worker waits for `0x3000 != 0`, executes one H4 descriptor, emits the
normal completion store at `0x2000`, waits for `0x3000 == 0`, and returns to
the first wait loop.

## Ownership Rules

[`safe_host_control.sv`](../h0_5_safe_host_control/rtl/safe_host_control.sv)
preserves legacy H3-H6 behavior until the first doorbell is used. In resident
mode, access is:

```text
State                         ARM shared RAM     Snitch shared RAM
Reset held                    allowed            reset
Resident idle, active = 0     allowed            worker polls doorbell only
Job active, active = 1        blocked            allowed
Completion observed           allowed            worker waits for release
```

This is explicit arbitration, not cache coherence and not unrestricted
simultaneous access. The underlying M10K remains true dual-port, but the
control plane prevents both processors from treating the payload as owned at
the same time.

## Repeatable Completion

Before H7, the shared-data responder held `result_valid` high until cluster
reset. That was correct when every job ended in reset, but it could not create
a second rising edge for a resident worker.

[`axi_shared_data_ram.sv`](../h3_shared_data_memory/rtl/axi_shared_data_ram.sv)
now accepts an explicit result acknowledgement. Ringing the next doorbell
clears the previous sticky valid state while preserving the result value.
The next completion store raises `result_valid` again, producing another
pending interrupt and another kernel event count.

## Software

[`firmware/resident_job.S`](firmware/resident_job.S) is a 220-byte RV32IMA
worker. It reuses the H4 descriptor validation and transform operation but
loops around the doorbell instead of looping forever after one completion.

H7 extends the H6 driver with the opt-in module parameter:

```text
resident_mode=0   H6 behavior: reset and restart each job
resident_mode=1   H7 behavior: release once and ring the doorbell per job
```

The shared H6 userspace ABI remains unchanged. The driver returns diagnostic
values in its two reserved words:

```text
reserved[0]   number of worker starts
reserved[1]   final JOB_DOORBELL ownership state
```

The client requires `worker starts == 1` and final state `0b110`: resident
mode active, host access allowed, no job active.

## Reproduce

Build the resident firmware, driver, and client:

```bash
cd /home/ftv/builds/hero-tools/fpga/de1-soc/h7_resident_worker
./scripts/test_build.sh
```

Rebuild the H7-capable FPGA image after RTL changes:

```bash
cd ../h0_5_safe_host_control
./scripts/build.sh
```

Run the physical proof:

```bash
cd ../h7_resident_worker
BOARD_SUDO_PASSWORD=temppwd ./scripts/run_board_test.sh
```

## Build Result

Verified with Quartus Prime Lite 25.1 on 2026-07-13:

```text
Logic utilization:     10,437 / 32,070 ALMs (33%)
Registers:             7,731
M10K blocks:           32 / 397 (8%)
Block memory bits:     235,264 / 4,065,280 (6%)
Worst setup slack:     +16.955 ns
Worst hold slack:      +0.123 ns
SOF and RBF:           generated
```

The first Qsys generation attempt ended in an OpenJDK 8 `SIGSEGV` inside
`java.util.Formatter`. Qsys had not reported an RTL validation error. A clean
rerun generated all 23 modules and 86 files, after which map, fit, assembler,
and timing completed successfully. This was a transient Quartus/JRE process
failure, not a design workaround.

## Physical Result

Verified on the DE1-SoC LXDE Linux image on 2026-07-13:

```text
H6_CLIENT_UID=0x000003e8
H6_PAYLOAD_UPLOADS=0x00000001
H7_JOB0_WORKER_STARTS=0x00000001
H6_JOB0_EVENT=0x00000001
H6_JOB0_PASS
H7_JOB1_WORKER_STARTS=0x00000001
H6_JOB1_EVENT=0x00000002
H6_JOB1_PASS
H7_JOB2_WORKER_STARTS=0x00000001
H6_JOB2_EVENT=0x00000003
H6_JOB2_PASS
H7_RESIDENT_WORKER_PASS
H6_LINUX_JOB_DRIVER_PASS
```

The test still runs the client as UID 1000 and still uses only
`/dev/snitch_job`. Kernel ownership from H6 and resident execution from H7 are
therefore proven together.

The H6 board script was also rerun against the H7-capable SOF with
`resident_mode=0` and returned `H6_LINUX_JOB_DRIVER_PASS`. This confirms that
reset-per-job behavior remains available and that H7 is an opt-in extension.

## Current Limitations

- One synchronous job may be active at a time.
- The worker busy-polls the doorbell; there is no Snitch sleep/wakeup event.
- Linux cannot prepare the next descriptor while Snitch owns the single
  payload buffer.
- There is no queue, sequence number, cancellation, or per-job timeout field.
- Firmware authenticity and persistent udev policy remain future work.

The next logical milestone is H8: add double-buffered descriptors with
per-slot ownership so Linux can prepare one job while Snitch executes another.

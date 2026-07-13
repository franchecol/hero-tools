#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h3_dir=$(cd -- "${script_dir}/.." && pwd)
de1_dir=$(cd -- "${h3_dir}/.." && pwd)
h0_dir="${de1_dir}/h0_5_safe_host_control"
sl14_dir="${de1_dir}/sl14_snitch_hps_irq_linux"
d3_dir="${de1_dir}/d3_hps_mmio_accel"
tty="${TTY:-/dev/ttyUSB0}"
password="${BOARD_SUDO_PASSWORD:?BOARD_SUDO_PASSWORD is required}"
export BOARD_USER="${BOARD_USER:-ubuntu}"
export BOARD_PASSWORD="${BOARD_PASSWORD:-temppwd}"

"${script_dir}/build_firmware.sh"
BOARD_KERNEL=lxde "${sl14_dir}/scripts/build_kernel_module.sh"
quartus_pgm -m jtag -c 1 -o "p;${h0_dir}/output_files/de1_h0_5_safe_cluster.sof@2"
"${d3_dir}/scripts/serial_transfer.py" --tty "${tty}" bootstrap \
  --receiver-binary "${d3_dir}/build/d3_serial_recv"
"${d3_dir}/scripts/serial_transfer.py" --tty "${tty}" send \
  "${sl14_dir}/build/snitch_lite_irq.ko" /tmp/snitch_lite_irq.ko

export H3_DIR="${h3_dir}" H3_SERIAL_RUN="${d3_dir}/scripts/serial_run.py"
export H3_TTY="${tty}" BOARD_SUDO_PASSWORD="${password}"
python3 - <<'PY'
import os
import shlex
import struct
import subprocess
from pathlib import Path

boot_base = 0xff201000
data_base = 0xff202000
password = os.environ["BOARD_SUDO_PASSWORD"]
binary = Path(os.environ["H3_DIR"]) / "build/shared_transform.bin"
data = binary.read_bytes() + bytes((-binary.stat().st_size) % 4)
upload = []
for index, (word,) in enumerate(struct.iter_unpack("<I", data)):
    upload.append(f"devmem2 {boot_base + index * 4:#x} w {word:#010x} >/dev/null")

inputs = [3, 7, 16, 256]
expected = [value * 3 + 7 for value in inputs]
commands = [
    "set -e",
    "rmmod snitch_lite_irq 2>/dev/null || true",
    "insmod /tmp/snitch_lite_irq.ko gic_spi=40 mmio_base=0xff200000 irq_pending_offset=0x18",
    "devmem2 0xff200004 w 0 >/dev/null",
    *upload,
]
for index, value in enumerate(inputs):
    commands.append(f"devmem2 {data_base + index * 4:#x} w {value:#x} >/dev/null")
commands += [
    "devmem2 0xff200018 w 1 >/dev/null",
    "devmem2 0xff200014 w 1 >/dev/null",
    "rm -f /tmp/h3_event",
    "dd if=/dev/snitch_lite_irq of=/tmp/h3_event bs=8 count=1 2>/dev/null & reader=$!",
    "sleep 1",
    "devmem2 0xff200004 w 1 >/dev/null",
    "wait $reader",
    "echo H3_IRQ_READER_WOKE",
    "sig=$(devmem2 0xff200010 w | awk '/Value at/{print $NF}')",
    "echo COMPLETION_SIGNATURE=$sig",
    "test \"$((sig))\" -eq $((0x4833))",
    "devmem2 0xff200004 w 0 >/dev/null",
]
for index, value in enumerate(expected):
    address = data_base + 0x40 + index * 4
    commands += [
        f"v=$(devmem2 {address:#x} w | awk '/Value at/{{print $NF}}')",
        f"echo OUTPUT{index}=$v",
        f'test "$((v))" -eq {value}',
    ]
commands += [
    "rmmod snitch_lite_irq",
]
remote = "; ".join(commands)
sudo = "printf '%s\\n' " + shlex.quote(password) + " | sudo -S sh -c " + shlex.quote(remote)
subprocess.run(
    [os.environ["H3_SERIAL_RUN"], "--tty", os.environ["H3_TTY"],
     "--stop-on-error", "--require", "H3_SHARED_DATA_PASS"],
    input=sudo + "\necho H3_SHARED_DATA_PASS\n", text=True, check=True)
PY

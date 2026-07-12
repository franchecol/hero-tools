#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h1_dir=$(cd -- "${script_dir}/.." && pwd)
de1_dir=$(cd -- "${h1_dir}/.." && pwd)
sl14_dir="${de1_dir}/sl14_snitch_hps_irq_linux"
d3_dir="${de1_dir}/d3_hps_mmio_accel"
tty="${TTY:-/dev/ttyUSB0}"

BOARD_KERNEL=lxde "${sl14_dir}/scripts/build_kernel_module.sh"
"${d3_dir}/scripts/serial_transfer.py" --tty "${tty}" bootstrap \
  --receiver-binary "${d3_dir}/build/d3_serial_recv"
"${d3_dir}/scripts/serial_transfer.py" --tty "${tty}" send \
  "${sl14_dir}/build/snitch_lite_irq.ko" /tmp/snitch_lite_irq.ko

export H1_SERIAL_RUN="${d3_dir}/scripts/serial_run.py"
export H1_TTY="${tty}"
python3 - <<'PY'
import os
import shlex
import subprocess

password = os.environ.get("BOARD_SUDO_PASSWORD")
if not password:
    raise SystemExit("BOARD_SUDO_PASSWORD is required")

def sudo(command):
    return "printf '%s\\n' " + shlex.quote(password) + " | sudo -S sh -c " + shlex.quote(command)

test_lines = r'''
rmmod snitch_lite_irq 2>/dev/null || true
insmod /tmp/snitch_lite_irq.ko gic_spi=40 mmio_base=0xff200000 irq_pending_offset=0x18
devmem2 0xff200004 w 0 >/dev/null
devmem2 0xff200018 w 1 >/dev/null
devmem2 0xff200014 w 1 >/dev/null
rm -f /tmp/h1_event
dd if=/dev/snitch_lite_irq of=/tmp/h1_event bs=8 count=1 2>/dev/null &
reader=$!
sleep 1
devmem2 0xff200004 w 1 >/dev/null
wait $reader
echo IRQ_READER_WOKE
set -- $(od -An -tx4 -v /tmp/h1_event)
test "$1" = 00000001
test "$2" = 00000007
od -An -tx4 -v /tmp/h1_event
test "$(devmem2 0xff200010 w | awk '/Value at/{print $NF}')" = 0x5A5
test "$(devmem2 0xff200018 w | awk '/Value at/{print $NF}')" = 0x2
devmem2 0xff200008 w
devmem2 0xff200010 w
devmem2 0xff200018 w
devmem2 0xff200004 w 0 >/dev/null
'''
parts = [line.strip() for line in test_lines.splitlines() if line.strip()]
test = " ".join(part if part.endswith("&") else part + ";" for part in parts)

commands = [
    "echo ---H1-UPSTREAM-IRQ---",
    sudo(test),
    "grep -E 'snitch|CPU' /proc/interrupts | tail -5",
    sudo("rmmod snitch_lite_irq"),
    "echo H1_IRQ_WAKE_PASS",
]
subprocess.run(
    [os.environ["H1_SERIAL_RUN"], "--tty", os.environ["H1_TTY"],
     "--stop-on-error", "--require", "H1_IRQ_WAKE_PASS"],
    input="\n".join(commands) + "\n",
    text=True,
    check=True,
)
PY

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S13_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
DE1_DIR=$(cd -- "${S13_DIR}/.." && pwd)
D3_DIR="${DE1_DIR}/d3_hps_mmio_accel"
TTY="${TTY:-/dev/ttyUSB0}"

"${SCRIPT_DIR}/build_arm_tester.sh"

"${D3_DIR}/scripts/serial_transfer.py" \
    --tty "${TTY}" \
    bootstrap \
    --receiver-binary "${D3_DIR}/build/d3_serial_recv"
"${D3_DIR}/scripts/serial_transfer.py" --tty "${TTY}" send \
    "${S13_DIR}/build/s13_irq_nolibc" \
    /tmp/s13_irq_nolibc
"${D3_DIR}/scripts/serial_transfer.py" --tty "${TTY}" send \
    "${S13_DIR}/generated/sw/s13_payload.bin" \
    /tmp/s13_payload.bin

export D3_SERIAL_RUN="${D3_DIR}/scripts/serial_run.py"
export TTY
python3 - <<'PY'
import os
import shlex
import subprocess

tty = os.environ.get("TTY", "/dev/ttyUSB0")
serial_run = os.environ["D3_SERIAL_RUN"]
sudo_password = os.environ.get("BOARD_SUDO_PASSWORD")


def sudo_cmd(command):
    if not sudo_password:
        return command
    return "printf '%s\\n' " + shlex.quote(sudo_password) + " | sudo -S sh -c " + shlex.quote(command)


def bridge_cmd():
    script = (
        'for name in lwhps2fpga hps2fpga fpga2hps; do '
        'if [ -e "/sys/class/fpga-bridge/$name/enable" ]; then '
        'echo 1 > "/sys/class/fpga-bridge/$name/enable"; '
        'printf "bridge %s=" "$name"; cat "/sys/class/fpga-bridge/$name/enable"; '
        'elif [ -d /sys/class/fpga_bridge ]; then '
        'for br in /sys/class/fpga_bridge/br*; do '
        '[ -e "$br/name" ] || continue; '
        '[ "$(cat "$br/name")" = "$name" ] || continue; '
        'printf "bridge %s=" "$name"; cat "$br/state"; '
        'done; '
        'else echo "bridge $name=missing"; fi; '
        'done'
    )
    return "sh -c " + shlex.quote(script)


commands = [
    "echo ---S13-IRQ-DONE---",
    "md5sum /tmp/s13_irq_nolibc /tmp/s13_payload.bin",
    bridge_cmd(),
    "chmod +x /tmp/s13_irq_nolibc",
    sudo_cmd("/tmp/s13_irq_nolibc") + "; rc=$?; echo TEST_RC=$rc",
    "echo __S13_IRQ_DONE__",
]

subprocess.run(
    [serial_run, "--tty", tty, "--require", "TEST_RC=0", "--require", "__S13_IRQ_DONE__"],
    input="\n".join(commands) + "\n",
    text=True,
    check=True,
)
PY

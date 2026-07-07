#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
DE1_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
D3_DIR="${DE1_DIR}/d3_hps_mmio_accel"
TTY="${TTY:-/dev/ttyUSB0}"

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


unbind_altvipfb = (
    'if [ -d /sys/bus/platform/drivers/altvipfb ]; then '
    'for dev in /sys/bus/platform/drivers/altvipfb/*; do '
    '[ -e "$dev/driver" ] || continue; '
    'echo "$(basename "$dev")" > /sys/bus/platform/drivers/altvipfb/unbind 2>/dev/null || true; '
    'done; '
    'fi'
)

commands = [
    "echo ---DE1-LXDE-HEADLESS-PREP---",
    "uname -a",
    "whoami",
    sudo_cmd("systemctl stop lightdm 2>/dev/null || true"),
    sudo_cmd("systemctl stop graphical.target 2>/dev/null || true"),
    sudo_cmd("systemctl isolate multi-user.target 2>/dev/null || true"),
    sudo_cmd("sh -c " + shlex.quote(unbind_altvipfb)),
    "echo fpga_bridges",
    "for b in /sys/class/fpga_bridge/br* /sys/class/fpga-bridge/*; do [ -e \"$b\" ] || continue; printf \"%s \" \"$b\"; cat \"$b/name\" 2>/dev/null || true; cat \"$b/state\" 2>/dev/null || cat \"$b/enable\" 2>/dev/null || true; done",
    "echo __DE1_LXDE_HEADLESS_PREP_DONE__",
]

subprocess.run(
    [serial_run, "--tty", tty, "--require", "__DE1_LXDE_HEADLESS_PREP_DONE__"],
    input="\n".join(commands) + "\n",
    text=True,
    check=True,
)
PY

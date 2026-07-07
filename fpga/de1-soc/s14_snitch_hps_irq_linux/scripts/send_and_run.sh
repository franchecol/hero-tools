#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S14_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
DE1_DIR=$(cd -- "${S14_DIR}/.." && pwd)
S13_DIR="${DE1_DIR}/s13_snitch_hps_irq_done"
D3_DIR="${DE1_DIR}/d3_hps_mmio_accel"
TTY="${TTY:-/dev/ttyUSB0}"
BOARD_KERNEL="${BOARD_KERNEL:-console}"
IRQ="${IRQ:-72}"
GIC_SPI="${GIC_SPI:-}"
GIC_HWIRQ="${GIC_HWIRQ:-}"

if [[ "${BOARD_KERNEL}" == "lxde" && -z "${GIC_SPI}" && -z "${GIC_HWIRQ}" ]]; then
    GIC_SPI=40
fi

"${SCRIPT_DIR}/build_kernel_module.sh"
"${SCRIPT_DIR}/build_arm_waiter.sh"
"${S13_DIR}/scripts/build_payload.sh"

"${D3_DIR}/scripts/serial_transfer.py" \
    --tty "${TTY}" \
    bootstrap \
    --receiver-binary "${D3_DIR}/build/d3_serial_recv"
"${D3_DIR}/scripts/serial_transfer.py" --tty "${TTY}" send \
    "${S14_DIR}/build/snitch_lite_irq.ko" \
    /tmp/snitch_lite_irq.ko
"${D3_DIR}/scripts/serial_transfer.py" --tty "${TTY}" send \
    "${S14_DIR}/build/s14_irq_wait_nolibc" \
    /tmp/s14_irq_wait_nolibc
"${D3_DIR}/scripts/serial_transfer.py" --tty "${TTY}" send \
    "${S13_DIR}/generated/sw/s13_payload.bin" \
    /tmp/s14_payload.bin

export D3_SERIAL_RUN="${D3_DIR}/scripts/serial_run.py"
export TTY IRQ GIC_SPI GIC_HWIRQ
python3 - <<'PY'
import os
import shlex
import subprocess

tty = os.environ.get("TTY", "/dev/ttyUSB0")
irq = os.environ.get("IRQ", "72")
gic_spi = os.environ.get("GIC_SPI", "")
gic_hwirq = os.environ.get("GIC_HWIRQ", "")
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
    "echo ---S14-IRQ-WAIT---",
    "uname -a",
    "md5sum /tmp/snitch_lite_irq.ko /tmp/s14_irq_wait_nolibc /tmp/s14_payload.bin",
    bridge_cmd(),
    sudo_cmd("rmmod snitch_lite_irq 2>/dev/null || true"),
    sudo_cmd(
        f"insmod /tmp/snitch_lite_irq.ko irq={irq} "
        + (f"gic_spi={gic_spi} " if gic_spi else "")
        + (f"gic_hwirq={gic_hwirq} " if gic_hwirq else "")
        + "mmio_base=0xff200000 irq_pending_offset=0x3c"
    ),
    "echo interrupts_before",
    f"sed -n '1,170p' /proc/interrupts | grep -E '(^ *{irq}:|snitch|CPU)' || true",
    "ls -l /dev/snitch_lite_irq",
    "chmod +x /tmp/s14_irq_wait_nolibc",
    sudo_cmd("/tmp/s14_irq_wait_nolibc") + "; rc=$?; echo TEST_RC=$rc",
    "echo interrupts_after",
    f"sed -n '1,170p' /proc/interrupts | grep -E '(^ *{irq}:|snitch|CPU)' || true",
    "dmesg | tail -30",
    sudo_cmd("rmmod snitch_lite_irq 2>/dev/null || true"),
    "echo __S14_IRQ_WAIT_DONE__",
]

subprocess.run(
    [serial_run, "--tty", tty, "--require", "TEST_RC=0", "--require", "__S14_IRQ_WAIT_DONE__"],
    input="\n".join(commands) + "\n",
    text=True,
    check=True,
)
PY

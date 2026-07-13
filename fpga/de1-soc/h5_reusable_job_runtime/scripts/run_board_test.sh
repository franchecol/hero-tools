#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h5_dir=$(cd -- "${script_dir}/.." && pwd)
de1_dir=$(cd -- "${h5_dir}/.." && pwd)
h0_dir="${de1_dir}/h0_5_safe_host_control"
h4_dir="${de1_dir}/h4_linux_job_runtime"
sl14_dir="${de1_dir}/sl14_snitch_hps_irq_linux"
d3_dir="${de1_dir}/d3_hps_mmio_accel"
tty="${TTY:-/dev/ttyUSB0}"
password="${BOARD_SUDO_PASSWORD:?BOARD_SUDO_PASSWORD is required}"

"${script_dir}/test_build.sh"
BOARD_KERNEL=lxde "${sl14_dir}/scripts/build_kernel_module.sh"
quartus_pgm -m jtag -c 1 -o "p;${h0_dir}/output_files/de1_h0_5_safe_cluster.sof@2"

transfer="${d3_dir}/scripts/serial_transfer.py"
"${transfer}" --tty "${tty}" bootstrap --receiver-binary "${d3_dir}/build/d3_serial_recv"
"${transfer}" --tty "${tty}" send "${sl14_dir}/build/snitch_lite_irq.ko" /tmp/snitch_lite_irq.ko
"${transfer}" --tty "${tty}" send "${h5_dir}/build/h5_host_nolibc" /tmp/h5_host_nolibc
"${transfer}" --tty "${tty}" send "${h4_dir}/build/h4_job.bin" /tmp/h5_payload.bin

export H5_SERIAL_RUN="${d3_dir}/scripts/serial_run.py" H5_TTY="${tty}"
export BOARD_SUDO_PASSWORD="${password}"
python3 - <<'PY'
import os
import shlex
import subprocess

password = os.environ["BOARD_SUDO_PASSWORD"]

def sudo(command):
    return "printf '%s\\n' " + shlex.quote(password) + " | sudo -S sh -c " + shlex.quote(command)

commands = [
    sudo("rmmod snitch_lite_irq 2>/dev/null || true; "
         "insmod /tmp/snitch_lite_irq.ko gic_spi=40 mmio_base=0xff200000 irq_pending_offset=0x18"),
    sudo("chmod +x /tmp/h5_host_nolibc; /tmp/h5_host_nolibc"),
    sudo("rmmod snitch_lite_irq"),
]
subprocess.run(
    [os.environ["H5_SERIAL_RUN"], "--tty", os.environ["H5_TTY"],
     "--timeout", "60", "--stop-on-error", "--require", "H5_REUSABLE_RUNTIME_PASS"],
    input="\n".join(commands) + "\n", text=True, check=True)
PY

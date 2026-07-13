#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h6_dir=$(cd -- "${script_dir}/.." && pwd)
de1_dir=$(cd -- "${h6_dir}/.." && pwd)
h0_dir="${de1_dir}/h0_5_safe_host_control"
h4_dir="${de1_dir}/h4_linux_job_runtime"
d3_dir="${de1_dir}/d3_hps_mmio_accel"
tty="${TTY:-/dev/ttyUSB0}"
password="${BOARD_SUDO_PASSWORD:?BOARD_SUDO_PASSWORD is required}"

"${script_dir}/test_build.sh"
quartus_pgm -m jtag -c 1 -o "p;${h0_dir}/output_files/de1_h0_5_safe_cluster.sof@2"
transfer="${d3_dir}/scripts/serial_transfer.py"
"${transfer}" --tty "${tty}" bootstrap --receiver-binary "${d3_dir}/build/d3_serial_recv"
"${transfer}" --tty "${tty}" send "${h6_dir}/build/snitch_job.ko" /tmp/snitch_job.ko
"${transfer}" --tty "${tty}" send "${h6_dir}/build/h6_client_nolibc" /tmp/h6_client_nolibc
"${transfer}" --tty "${tty}" send "${h4_dir}/build/h4_job.bin" /tmp/h6_payload.bin

export H6_SERIAL_RUN="${d3_dir}/scripts/serial_run.py" H6_TTY="${tty}"
export BOARD_SUDO_PASSWORD="${password}"
python3 - <<'PY'
import os
import shlex
import subprocess

password = os.environ["BOARD_SUDO_PASSWORD"]

def sudo(command):
    return "printf '%s\\n' " + shlex.quote(password) + " | sudo -S sh -c " + shlex.quote(command)

commands = [
    sudo("rmmod snitch_lite_irq 2>/dev/null || true; rmmod snitch_job 2>/dev/null || true; "
         "insmod /tmp/snitch_job.ko gic_spi=40; "
         "i=0; while [ ! -e /dev/snitch_job ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done; "
         "sleep 1; chmod 666 /dev/snitch_job; test -r /dev/snitch_job -a -w /dev/snitch_job"),
    "chmod +x /tmp/h6_client_nolibc; /tmp/h6_client_nolibc",
    sudo("rmmod snitch_job"),
]
subprocess.run(
    [os.environ["H6_SERIAL_RUN"], "--tty", os.environ["H6_TTY"],
     "--timeout", "60", "--stop-on-error", "--require", "H6_LINUX_JOB_DRIVER_PASS"],
    input="\n".join(commands) + "\n", text=True, check=True)
PY

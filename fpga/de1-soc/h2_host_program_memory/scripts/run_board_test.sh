#!/usr/bin/env bash
set -euo pipefail
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
h2_dir=$(cd -- "${script_dir}/.." && pwd)
de1_dir=$(cd -- "${h2_dir}/.." && pwd)
h0_dir="${de1_dir}/h0_5_safe_host_control"
serial_run="${de1_dir}/d3_hps_mmio_accel/scripts/serial_run.py"
tty="${TTY:-/dev/ttyUSB0}"
password="${BOARD_SUDO_PASSWORD:?BOARD_SUDO_PASSWORD is required}"

"${script_dir}/build_programs.sh"
quartus_pgm -m jtag -c 1 -o "p;${h0_dir}/output_files/de1_h0_5_safe_cluster.sof@2"

export H2_DIR="${h2_dir}" H2_SERIAL_RUN="${serial_run}" H2_TTY="${tty}"
export BOARD_SUDO_PASSWORD="${password}"
python3 - <<'PY'
import os
import shlex
import struct
import subprocess
from pathlib import Path

base = 0xff201000
password = os.environ["BOARD_SUDO_PASSWORD"]

def writes(path):
    data = Path(path).read_bytes()
    data += bytes((-len(data)) % 4)
    commands = []
    for index, (word,) in enumerate(struct.iter_unpack("<I", data)):
        commands.append(f"devmem2 {base + index * 4:#x} w {word:#010x} >/dev/null")
    return "; ".join(commands)

def job(tag, binary, expected):
    return "; ".join([
        "devmem2 0xff200004 w 0 >/dev/null", writes(binary),
        "devmem2 0xff200004 w 1 >/dev/null", "sleep 1", f"echo {tag}",
        "devmem2 0xff200008 w",
        "v=$(devmem2 0xff200010 w | awk '/Value at/{print $NF}')",
        f"echo {tag}_RESULT=$v", f'test "$v" = {expected}',
        "devmem2 0xff200004 w 0 >/dev/null",
    ])

h2 = Path(os.environ["H2_DIR"])
test = "set -e; " + job("PROGRAM0", h2 / "build/program_5a5.bin", "0x5A5")
test += "; " + job("PROGRAM1", h2 / "build/program_3c3.bin", "0x3C3")
sudo = "printf '%s\\n' " + shlex.quote(password) + " | sudo -S sh -c " + shlex.quote(test)
subprocess.run(
    [os.environ["H2_SERIAL_RUN"], "--tty", os.environ["H2_TTY"],
     "--stop-on-error", "--require", "H2_TWO_PROGRAMS_PASS"],
    input=sudo + "\necho H2_TWO_PROGRAMS_PASS\n", text=True, check=True)
PY

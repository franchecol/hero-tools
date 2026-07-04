#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
S12_DIR=$(cd -- "${SCRIPT_DIR}/.." && pwd)
DE1_DIR=$(cd -- "${S12_DIR}/.." && pwd)
D3_DIR="${DE1_DIR}/d3_hps_mmio_accel"
TTY="${TTY:-/dev/ttyUSB0}"

"${SCRIPT_DIR}/build.sh"

"${D3_DIR}/scripts/serial_transfer.py" \
    --tty "${TTY}" \
    bootstrap \
    --receiver-binary "${D3_DIR}/build/d3_serial_recv"
"${D3_DIR}/scripts/serial_transfer.py" --tty "${TTY}" send \
    "${S12_DIR}/build/s12_file_loader_nolibc" \
    /tmp/s12_file_loader_nolibc
"${D3_DIR}/scripts/serial_transfer.py" --tty "${TTY}" send \
    "${S12_DIR}/generated/sw/s12_payload.bin" \
    /tmp/s12_payload.bin

python3 - <<'PY'
import os
import serial
import time

tty = os.environ.get("TTY", "/dev/ttyUSB0")
marker = "__S12_FILE_LOADER_DONE__"
cmd = r'''
echo ---S12-FILE-LOADER---
md5sum /tmp/s12_file_loader_nolibc /tmp/s12_payload.bin
for b in lwhps2fpga hps2fpga fpga2hps; do echo 1 > /sys/class/fpga-bridge/$b/enable; printf "bridge %s=" "$b"; cat /sys/class/fpga-bridge/$b/enable; done
chmod +x /tmp/s12_file_loader_nolibc
/tmp/s12_file_loader_nolibc
rc=$?
echo TEST_RC=$rc
echo __S12_FILE_LOADER_DONE__
'''

with serial.Serial(tty, 115200, timeout=0.1, write_timeout=10) as ser:
    ser.write(b'\x03stty sane\r')
    time.sleep(0.2)
    ser.read(8192)
    ser.write(cmd.replace('\n', '\r').encode())
    deadline = time.time() + 30
    out = bytearray()
    while time.time() < deadline:
        chunk = ser.read(4096)
        if chunk:
            out += chunk
            if marker.encode() in out:
                break
    text = out.decode("utf-8", errors="replace")
    print(text)
    if marker.encode() not in out:
        raise SystemExit("timeout waiting for S12 marker")
    if "TEST_RC=0" not in text:
        raise SystemExit("S12 test did not return 0")
PY

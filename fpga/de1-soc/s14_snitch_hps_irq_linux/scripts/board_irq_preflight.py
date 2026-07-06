#!/usr/bin/env python3
import os
import serial
import sys
import time


TTY = os.environ.get("TTY", "/dev/ttyUSB0")
BAUD = int(os.environ.get("BAUD", "115200"))


COMMANDS = [
    "echo ---S14-IRQ-PREFLIGHT---",
    "uname -a",
    "id",
    "echo dev_uio; ls -l /dev/uio* 2>/dev/null || true",
    "echo proc_interrupts; sed -n '1,120p' /proc/interrupts",
    "echo kernel_config; zcat /proc/config.gz 2>/dev/null | grep -E 'CONFIG_MODULES|CONFIG_MODULE_UNLOAD|CONFIG_DEVTMPFS|CONFIG_UIO|CONFIG_OF_IRQ' || true",
    "echo modules_tree; uname -r; ls -ld /lib/modules /lib/modules/$(uname -r) 2>/dev/null || true; find /lib/modules -maxdepth 3 -type f 2>/dev/null | sed -n '1,80p' || true",
    "echo stale_gpio_module; modinfo /lib/modules/3.9.0/extra/gpio_interrupt.ko 2>/dev/null || true",
    "echo device_tree_interrupt_files; find /proc/device-tree -maxdepth 5 -type f -name interrupts 2>/dev/null | sed -n '1,120p'",
]


def read_for(ser, seconds):
    deadline = time.time() + seconds
    out = bytearray()
    while time.time() < deadline:
        chunk = ser.read(4096)
        if chunk:
            out += chunk
    return bytes(out)


def ensure_shell(ser):
    ser.write(b"\x03\r")
    time.sleep(0.3)
    out = read_for(ser, 1.0)

    if b"login:" in out:
        ser.write(b"root\r")
        time.sleep(1.0)
        out += read_for(ser, 1.0)

    if b"Password:" in out:
        ser.write(b"\r")
        time.sleep(1.0)
        out += read_for(ser, 1.0)

    ser.write(b"echo __S14_SHELL_READY__\r")
    out += read_for(ser, 1.0)
    if b"__S14_SHELL_READY__" not in out:
        sys.stdout.buffer.write(out)
        raise SystemExit("could not establish board shell")


def run_block(ser):
    marker = "__S14_IRQ_PREFLIGHT_DONE__"
    for cmd in COMMANDS:
        ser.write((cmd + "\r").encode())
        time.sleep(0.08)
    ser.write(("echo " + marker + "\r").encode())

    deadline = time.time() + 20
    out = bytearray()
    while time.time() < deadline:
        chunk = ser.read(4096)
        if chunk:
            out += chunk
            if marker.encode() in out:
                break

    sys.stdout.buffer.write(bytes(out))
    if marker.encode() not in out:
        raise SystemExit("timed out waiting for preflight marker")


def main():
    with serial.Serial(TTY, BAUD, timeout=0.1, write_timeout=10) as ser:
        ensure_shell(ser)
        ser.write(b"stty sane -echo\r")
        time.sleep(0.2)
        ser.read(8192)
        run_block(ser)


if __name__ == "__main__":
    main()

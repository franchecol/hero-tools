#!/usr/bin/env python3
"""Run board shell commands over the DE1-SoC UART.

Commands are read from stdin, one command per line. Each command is wrapped with
a sentinel so the host waits for completion before sending the next command.
"""

import argparse
import os
import re
import sys
import time

from board_uart import ensure_shell, open_uart, read_until_marker


def parse_args():
    parser = argparse.ArgumentParser(description="run DE1-SoC shell commands over UART")
    parser.add_argument("--tty", default="/dev/ttyUSB0")
    parser.add_argument("--login-user", default=os.environ.get("BOARD_USER"))
    parser.add_argument("--login-password", default=os.environ.get("BOARD_PASSWORD"))
    parser.add_argument("--timeout", type=float, default=45.0)
    parser.add_argument("--require", action="append", default=[])
    parser.add_argument("--stop-on-error", action="store_true")
    return parser.parse_args()


def read_commands():
    commands = []
    for line in sys.stdin:
        command = line.strip()
        if not command or command.startswith("#"):
            continue
        commands.append(command)
    return commands


def run_command(ser, index, command, timeout):
    token = f"__SERIAL_RUN_{index:03d}_DONE__"
    wrapped = f"{command}; rc=$?; echo {token}$rc\r"
    ser.write(wrapped.encode())
    output = read_until_marker(ser, token, timeout, echo=True).decode("utf-8", errors="replace")
    match = re.search(rf"{re.escape(token)}([0-9]+)", output)
    if not match:
        raise RuntimeError(f"missing command status marker {token}")
    return output, int(match.group(1))


def main():
    args = parse_args()
    commands = read_commands()

    with open_uart(args.tty) as ser:
        ensure_shell(ser, args.login_user, args.login_password)
        ser.write(b"stty -echo\r")
        time.sleep(0.2)
        ser.read(8192)

        all_output = []
        try:
            for index, command in enumerate(commands):
                output, rc = run_command(ser, index, command, args.timeout)
                all_output.append(output)
                if args.stop_on_error and rc != 0:
                    raise SystemExit(f"command {index} failed with rc={rc}: {command}")
        finally:
            ser.write(b"stty echo\r")

    text = "".join(all_output)
    missing = [needle for needle in args.require if needle not in text]
    if missing:
        raise SystemExit(f"missing required board output: {', '.join(missing)}")


if __name__ == "__main__":
    main()

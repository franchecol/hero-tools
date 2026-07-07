#!/usr/bin/env python3
import argparse
import hashlib
import os
import pathlib
import re
import sys
import time

from board_uart import ensure_shell, open_uart, read_until_marker


def remote_verify_command(args, remote_file):
    if args.verify == "md5":
        return f"md5sum {remote_file}; "
    if args.verify == "size":
        return f"ls -l {remote_file}; "
    return ""


def check_remote_file(args, output, local_md5, size, label):
    if args.verify == "md5":
        if local_md5 not in output:
            print(output, file=sys.stderr)
            raise SystemExit(f"target {label} MD5 did not match {local_md5}")
        return f"md5={local_md5}"

    if args.verify == "size":
        if not re.search(rf"\s{size}\s", output):
            print(output, file=sys.stderr)
            raise SystemExit(f"target {label} size did not match {size}")
        return f"size={size}"

    return "not verified"


def bootstrap_receiver(args):
    receiver = pathlib.Path(args.receiver_binary)
    data = receiver.read_bytes()
    size = len(data)
    local_md5 = hashlib.md5(data).hexdigest()
    marker = "__D3_RECV_BOOTSTRAPPED__"

    with open_uart(args.tty) as ser:
        ensure_shell(ser, args.login_user, args.login_password)
        ser.write(b"stty -echo\r")
        time.sleep(0.1)
        ser.read(8192)
        ser.write(f": > {args.remote_receiver}\r".encode())
        time.sleep(0.05)

        for off in range(0, len(data), args.printf_chunk):
            escaped = "".join(f"\\x{byte:02x}" for byte in data[off:off + args.printf_chunk])
            ser.write(f"printf '{escaped}' >> {args.remote_receiver}\r".encode())
            time.sleep(0.02)

        cmd = (
            f"stty echo; "
            f"chmod +x {args.remote_receiver}; "
            f"{remote_verify_command(args, args.remote_receiver)}"
            f"echo {marker}\r"
        )
        ser.write(cmd.encode())
        output = read_until_marker(ser, marker, 20).decode("utf-8", errors="replace")

    verified = check_remote_file(args, output, local_md5, size, "receiver")

    print(f"receiver ok: {args.remote_receiver} {verified}")


def send_file(args):
    local = pathlib.Path(args.local_file)
    data = local.read_bytes()
    size = len(data)
    local_md5 = hashlib.md5(data).hexdigest()
    marker = "__D3_SERIAL_SEND_DONE__"

    with open_uart(args.tty) as ser:
        ensure_shell(ser, args.login_user, args.login_password)
        cmd = (
            "stty raw -echo -ixon -ixoff; "
            f"{args.remote_receiver} {args.remote_file} {size}; "
            "stty sane; "
            f"{remote_verify_command(args, args.remote_file)}"
            f"echo {marker}\r"
        )
        ser.write(cmd.encode())
        time.sleep(0.5)

        start = time.time()
        last_report = 0
        sent = 0
        for off in range(0, size, args.raw_chunk):
            chunk = data[off:off + args.raw_chunk]
            ser.write(chunk)
            sent += len(chunk)
            time.sleep(len(chunk) / args.rate)

            if args.progress and (sent - last_report >= args.progress_bytes or sent == size):
                elapsed = max(time.time() - start, 0.001)
                rate = sent / elapsed
                pct = sent * 100.0 / size
                print(f"{sent}/{size} bytes {pct:.1f}% {rate:.0f} B/s", file=sys.stderr)
                last_report = sent

        ser.flush()
        output = read_until_marker(ser, marker, args.timeout).decode("utf-8", errors="replace")

    verified = check_remote_file(args, output, local_md5, size, "file")

    print(f"file ok: {args.remote_file} {verified}")


def main():
    parser = argparse.ArgumentParser(description="DE1-SoC D3 UART file transfer helper")
    parser.add_argument("--tty", default="/dev/ttyUSB0")
    parser.add_argument("--remote-receiver", default="/tmp/d3_serial_recv")
    parser.add_argument("--login-user", default=os.environ.get("BOARD_USER"))
    parser.add_argument("--login-password", default=os.environ.get("BOARD_PASSWORD"))
    parser.add_argument(
        "--verify",
        choices=("size", "md5", "none"),
        default=os.environ.get("BOARD_VERIFY", "size"),
        help="board-side transfer verification; use md5 on images where md5sum works",
    )

    subparsers = parser.add_subparsers(dest="cmd", required=True)

    boot = subparsers.add_parser("bootstrap", help="copy d3_serial_recv to the board")
    boot.add_argument(
        "--receiver-binary",
        default="build/d3_serial_recv",
        help="local ARM receiver binary built by scripts/build_arm_tester.sh",
    )
    boot.add_argument("--printf-chunk", type=int, default=160)
    boot.set_defaults(func=bootstrap_receiver)

    send = subparsers.add_parser("send", help="send a file through the bootstrapped receiver")
    send.add_argument("local_file")
    send.add_argument("remote_file")
    send.add_argument("--raw-chunk", type=int, default=512)
    send.add_argument("--rate", type=float, default=9500.0, help="bytes per second")
    send.add_argument("--timeout", type=float, default=60.0)
    send.add_argument("--progress", action="store_true")
    send.add_argument("--progress-bytes", type=int, default=524288)
    send.set_defaults(func=send_file)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()

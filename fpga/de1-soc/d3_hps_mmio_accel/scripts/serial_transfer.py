#!/usr/bin/env python3
import argparse
import hashlib
import pathlib
import sys
import time

import serial


def open_uart(tty):
    return serial.Serial(tty, 115200, timeout=0.1, write_timeout=10)


def read_until_marker(ser, marker, timeout_s):
    deadline = time.time() + timeout_s
    marker_b = marker.encode()
    out = bytearray()

    while time.time() < deadline:
        chunk = ser.read(4096)
        if chunk:
            out += chunk
            if marker_b in out:
                return bytes(out)

    raise TimeoutError(f"timed out waiting for {marker}")


def reset_shell(ser):
    ser.write(b"\x03stty sane\r")
    time.sleep(0.2)
    ser.read(8192)


def bootstrap_receiver(args):
    receiver = pathlib.Path(args.receiver_binary)
    data = receiver.read_bytes()
    local_md5 = hashlib.md5(data).hexdigest()
    marker = "__D3_RECV_BOOTSTRAPPED__"

    with open_uart(args.tty) as ser:
        reset_shell(ser)
        ser.write(f": > {args.remote_receiver}\r".encode())
        time.sleep(0.05)

        for off in range(0, len(data), args.printf_chunk):
            escaped = "".join(f"\\x{byte:02x}" for byte in data[off:off + args.printf_chunk])
            ser.write(f"printf '{escaped}' >> {args.remote_receiver}\r".encode())
            time.sleep(0.02)

        cmd = (
            f"chmod +x {args.remote_receiver}; "
            f"md5sum {args.remote_receiver}; "
            f"echo {marker}\n"
        )
        ser.write(cmd.encode())
        output = read_until_marker(ser, marker, 20).decode("utf-8", errors="replace")

    if local_md5 not in output:
        print(output, file=sys.stderr)
        raise SystemExit(f"target receiver MD5 did not match {local_md5}")

    print(f"receiver ok: {args.remote_receiver} md5={local_md5}")


def send_file(args):
    local = pathlib.Path(args.local_file)
    data = local.read_bytes()
    size = len(data)
    local_md5 = hashlib.md5(data).hexdigest()
    marker = "__D3_SERIAL_SEND_DONE__"

    with open_uart(args.tty) as ser:
        reset_shell(ser)
        cmd = (
            "stty raw -echo -ixon -ixoff; "
            f"{args.remote_receiver} {args.remote_file} {size}; "
            "stty sane; "
            f"md5sum {args.remote_file}; "
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

    if local_md5 not in output:
        print(output, file=sys.stderr)
        raise SystemExit(f"target file MD5 did not match {local_md5}")

    print(f"file ok: {args.remote_file} md5={local_md5}")


def main():
    parser = argparse.ArgumentParser(description="DE1-SoC D3 UART file transfer helper")
    parser.add_argument("--tty", default="/dev/ttyUSB0")
    parser.add_argument("--remote-receiver", default="/tmp/d3_serial_recv")

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

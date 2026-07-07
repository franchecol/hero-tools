#!/usr/bin/env python3
"""Small UART helpers shared by the DE1-SoC board scripts."""

import time

import serial


def open_uart(tty):
    return serial.Serial(tty, 115200, timeout=0.1, write_timeout=10)


def drain(ser, quiet_s=0.25, timeout_s=1.0):
    deadline = time.time() + timeout_s
    last_rx = time.time()
    out = bytearray()

    while time.time() < deadline:
        chunk = ser.read(4096)
        if chunk:
            out += chunk
            last_rx = time.time()
        elif out and time.time() - last_rx >= quiet_s:
            break

    return bytes(out)


def read_until_marker(ser, marker, timeout_s, echo=False):
    deadline = time.time() + timeout_s
    marker_b = marker.encode()
    out = bytearray()

    while time.time() < deadline:
        chunk = ser.read(4096)
        if chunk:
            out += chunk
            if echo:
                print(chunk.decode("utf-8", errors="replace"), end="", flush=True)
            if marker_b in out:
                return bytes(out)

    raise TimeoutError(f"timed out waiting for {marker}")


def _has_login_prompt(data):
    lower = data.lower()
    return b" login:" in lower or lower.rstrip().endswith(b"login:")


def _has_password_prompt(data):
    return b"password:" in data.lower()


def ensure_shell(ser, login_user=None, login_password=None):
    """Reach a usable shell prompt.

    Old console images are commonly already logged in as root. The LXDE image
    starts at a login prompt, so BOARD_USER/BOARD_PASSWORD can be used by the
    scripts without changing the transfer protocol.
    """
    marker = "__BOARD_UART_READY__"
    last_output = bytearray()

    for attempt in range(4):
        if attempt == 0:
            ser.write(b"\r")
        else:
            ser.write(b"\x03\r")
        time.sleep(0.35)
        output = drain(ser, timeout_s=5.0)
        last_output += output

        sent_login = False
        if _has_login_prompt(output):
            if not login_user:
                raise RuntimeError("board is at a login prompt; set BOARD_USER")
            ser.write(f"{login_user}\r".encode())
            sent_login = True
            time.sleep(0.6)
            output = drain(ser, timeout_s=3.0)
            last_output += output

        if sent_login and not _has_password_prompt(output):
            for _ in range(3):
                time.sleep(0.8)
                extra = drain(ser, timeout_s=1.5)
                output += extra
                last_output += extra
                if _has_password_prompt(output):
                    break
            if not _has_password_prompt(output):
                continue

        if _has_password_prompt(output):
            if login_password is None:
                raise RuntimeError("board is asking for a password; set BOARD_PASSWORD")
            ser.write(f"{login_password}\r".encode())
            time.sleep(1.0)
            output = drain(ser, timeout_s=3.0)
            last_output += output

        ser.write(b"\x03\r")
        time.sleep(0.1)
        ser.write(b"stty sane\r")
        time.sleep(0.2)
        ser.read(8192)
        ser.write(f"echo {marker}\r".encode())
        try:
            read_until_marker(ser, marker, 8)
            return
        except TimeoutError:
            last_output += drain(ser, timeout_s=1.5)

    tail = bytes(last_output[-1000:]).decode("utf-8", errors="replace")
    raise TimeoutError(f"timed out waiting for {marker}; last board output:\n{tail}")

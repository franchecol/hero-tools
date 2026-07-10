#!/usr/bin/env python3
import re
import sys
from pathlib import Path


def parse_hex_field(line: str, field: str) -> int | None:
    match = re.search(rf"'{re.escape(field)}': 0x([0-9a-fA-F]+)", line)
    if not match:
        return None
    return int(match.group(1), 16)


def main() -> int:
    if len(sys.argv) != 4:
        print(
            "usage: check_mmio_trace.py TRACE_PATH EXPECTED_ADDR EXPECTED_VALUE",
            file=sys.stderr,
        )
        return 2

    trace_path = Path(sys.argv[1])
    expected_addr = int(sys.argv[2], 0)
    expected_value = int(sys.argv[3], 0)

    if not trace_path.is_file():
        print(f"missing trace file: {trace_path}", file=sys.stderr)
        return 1

    stores: list[tuple[int, int, int]] = []
    for lineno, line in enumerate(trace_path.read_text().splitlines(), start=1):
        is_store = parse_hex_field(line, "is_store")
        if is_store != 1:
            continue

        addr = parse_hex_field(line, "alu_result")
        value = parse_hex_field(line, "gpr_rdata_1")
        if addr is None or value is None:
            continue

        stores.append((lineno, addr, value))
        if addr == expected_addr and value == expected_value:
            print(
                "found expected MMIO store: "
                f"line={lineno} addr=0x{addr:08x} value=0x{value:08x}"
            )
            return 0

    print(
        "expected MMIO store not found: "
        f"addr=0x{expected_addr:08x} value=0x{expected_value:08x}",
        file=sys.stderr,
    )
    if stores:
        print("observed stores:", file=sys.stderr)
        for lineno, addr, value in stores[:8]:
            print(
                f"  line={lineno} addr=0x{addr:08x} value=0x{value:08x}",
                file=sys.stderr,
            )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

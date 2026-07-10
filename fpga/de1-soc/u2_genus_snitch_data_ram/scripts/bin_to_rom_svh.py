#!/usr/bin/env python3
"""Convert a little-endian RV32 binary into the U2 ROM function."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("binary", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    data = args.binary.read_bytes()
    if not data or len(data) % 4 != 0:
        raise SystemExit("ROM binary must be non-empty and 4-byte aligned")

    words = [
        int.from_bytes(data[offset : offset + 4], byteorder="little")
        for offset in range(0, len(data), 4)
    ]

    lines = [
        "// Generated from sw/ram_check.S. Do not edit.",
        f"localparam int unsigned S19_ROM_WORDS = {len(words)};",
        "",
        "function automatic logic [31:0] s19_rom_word(",
        "    input logic [31:0] word_index",
        ");",
        "  unique case (word_index)",
    ]
    for index, word in enumerate(words):
        lines.append(f"    32'd{index}: s19_rom_word = 32'h{word:08x};")
    lines.extend(
        [
            "    default: s19_rom_word = 32'h0000006f;",
            "  endcase",
            "endfunction",
            "",
        ]
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n".join(lines), encoding="utf-8")


if __name__ == "__main__":
    main()

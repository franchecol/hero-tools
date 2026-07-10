#!/usr/bin/env python3
"""Replace Verilog escaped identifiers with deterministic simple names."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


ESCAPED_IDENTIFIER = re.compile(r"\\([^\s]+)")


def sanitize(text: str) -> tuple[str, int]:
    names: set[str] = set()

    def replace(match: re.Match[str]) -> str:
        original = match.group(1)
        names.add(original)
        return "esc_" + original.encode("utf-8").hex()

    return ESCAPED_IDENTIFIER.sub(replace, text), len(names)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    sanitized, count = sanitize(args.input.read_text(encoding="utf-8"))
    args.output.write_text(sanitized, encoding="utf-8")
    print(f"Sanitized {count} distinct escaped identifiers")


if __name__ == "__main__":
    main()

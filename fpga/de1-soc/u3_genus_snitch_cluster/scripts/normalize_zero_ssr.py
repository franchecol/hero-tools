#!/usr/bin/env python3
"""Repair the zero-SSR array emitted by this pinned clustergen revision."""

import argparse
from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise SystemExit(f"expected exactly one {label} block")
    return text.replace(old, new)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("wrapper", type=Path)
    args = parser.parse_args()

    text = args.wrapper.read_text()
    text = replace_once(
        text,
        """  localparam snitch_ssr_pkg::ssr_cfg_t [0-1:0] SsrCfgs [1] = '{

  };

  localparam logic [0-1:0][4:0] SsrRegs [1] = '{

  };""",
        """  // One inert slot avoids the zero-width array emitted when Xssr is disabled.
  localparam snitch_ssr_pkg::ssr_cfg_t [1-1:0] SsrCfgs [1] = '{default: '0};

  localparam logic [1-1:0][4:0] SsrRegs [1] = '{default: '0};""",
        "zero-SSR",
    )
    text = replace_once(
        text,
        ".NumSsrsMax (0)",
        ".NumSsrsMax (1)",
        "NumSsrsMax",
    )
    args.wrapper.write_text(text)


if __name__ == "__main__":
    main()

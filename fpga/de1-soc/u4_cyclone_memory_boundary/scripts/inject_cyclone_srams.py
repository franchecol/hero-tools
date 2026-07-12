#!/usr/bin/env python3
"""Replace Genus SRAM logic abstracts with fixed-width Cyclone implementations."""

import argparse
import json
import re
from pathlib import Path


PREFIX = "tc_sram_impl_"
SUFFIX = "_ByteWidth8_NumPorts1_Latency1_impl_in_ttype_de1_u3_snitch_cluster_pkg_sram_cfg_t_49_25"


def module_text(words: int, width: int, addr_width: int, be_width: int) -> str:
    name = f"{PREFIX}NumWords{words}_DataWidth{width}{SUFFIX}"
    target = f"cyclone_sram_{words}x{width}"
    return f"""module {name}(clk_i, rst_ni, \\impl_i[reserved] , impl_o, req_i,
     we_i, \\addr_i[0] , \\wdata_i[0] , \\be_i[0] , \\rdata_o[0] );
  input clk_i, rst_ni;
  input [0:0] \\impl_i[reserved] , req_i, we_i;
  input [{addr_width - 1}:0] \\addr_i[0] ;
  input [{width - 1}:0] \\wdata_i[0] ;
  input [{be_width - 1}:0] \\be_i[0] ;
  output impl_o;
  output [{width - 1}:0] \\rdata_o[0] ;

  assign impl_o = 1'b0;
  {target} i_cyclone_mem (
    .clk_i (clk_i),
    .req_i (req_i[0]),
    .we_i (we_i[0]),
    .addr_i (\\addr_i[0] ),
    .wdata_i (\\wdata_i[0] ),
    .be_i (\\be_i[0] ),
    .rdata_o (\\rdata_o[0] )
  );
endmodule"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--name-map", type=Path)
    args = parser.parse_args()

    text = args.input.read_text()
    for geometry in ((512, 64, 9, 8), (128, 128, 7, 16), (128, 24, 7, 3)):
        replacement = module_text(*geometry)
        name = replacement.split("(", 1)[0].removeprefix("module ")
        pattern = rf"module\s+{re.escape(name)}\(.*?endmodule"
        text, count = re.subn(pattern, lambda _: replacement, text, count=1, flags=re.DOTALL)
        if count != 1:
            raise SystemExit(f"expected one empty module named {name}, found {count}")

    # Genus encodes every parameter and type value in specialized module names.
    # Quartus crashes on the 2405-character cluster identifier, so shorten only
    # generated module identifiers that exceed a conservative Verilog limit.
    module_names = re.findall(r"(?m)^module\s+(\S+?)\s*\(", text)
    long_names = sorted(name for name in module_names if len(name) > 240)
    for index, name in enumerate(long_names):
        text, count = re.subn(rf"\b{re.escape(name)}\b", f"u4_genus_module_{index}", text)
        if count < 2:
            raise SystemExit(f"specialized module {name} was not instantiated")

    # Genus preserves hierarchy and array indices in escaped identifiers. The
    # Quartus SGN frontend interprets parts of those names as group dimensions
    # and crashes while constructing its internal name table. Rename each
    # escaped token consistently; this changes names only, never connectivity.
    escaped_names: dict[str, str] = {}

    def shorten_escaped(match: re.Match[str]) -> str:
        name = match.group(0)
        if name not in escaped_names:
            if name.startswith(("\\narrow_in_", "\\narrow_out_", "\\wide_in_", "\\wide_out_")):
                semantic = re.sub(r"[^A-Za-z0-9_]+", "_", name.removeprefix("\\")).strip("_")
                escaped_names[name] = semantic
            else:
                escaped_names[name] = f"u4_escaped_{len(escaped_names)}"
        return escaped_names[name]

    text = re.sub(r"\\\S+", shorten_escaped, text)

    if args.name_map:
        args.name_map.write_text(
            json.dumps(
                {
                    "escaped_identifiers": escaped_names,
                    "long_modules": {
                        name: f"u4_genus_module_{index}"
                        for index, name in enumerate(long_names)
                    },
                },
                indent=2,
                sort_keys=True,
            )
            + "\n"
        )

    args.output.write_text(text)


if __name__ == "__main__":
    main()

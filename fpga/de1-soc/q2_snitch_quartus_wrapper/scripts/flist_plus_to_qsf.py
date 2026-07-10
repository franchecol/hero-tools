#!/usr/bin/env python3
import sys
from pathlib import Path


def qsf_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit_assignment(name: str, value: str) -> str:
    return f"set_global_assignment -name {name} {qsf_quote(value)}"


def file_assignment(path: str) -> str:
    suffix = Path(path).suffix.lower()
    if suffix in {".sv", ".svh"}:
        return emit_assignment("SYSTEMVERILOG_FILE", path)
    if suffix == ".v":
        return emit_assignment("VERILOG_FILE", path)
    if suffix in {".vhd", ".vhdl"}:
        return emit_assignment("VHDL_FILE", path)
    return emit_assignment("MISC_FILE", path)


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: flist_plus_to_qsf.py INPUT.flist-plus OUTPUT.qsf", file=sys.stderr)
        return 2

    input_path = Path(sys.argv[1])
    output_path = Path(sys.argv[2])

    include_dirs: list[str] = []
    defines: list[str] = []
    files: list[str] = []

    for raw_line in input_path.read_text().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("+incdir+"):
            include_dirs.append(line.removeprefix("+incdir+"))
        elif line.startswith("+define+"):
            defines.append(line.removeprefix("+define+"))
        else:
            files.append(line)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w") as out:
        out.write("# Generated from Bender flist-plus. Do not edit by hand.\n")
        out.write("# Regenerate with scripts/export_quartus_project.sh.\n\n")

        for include_dir in include_dirs:
            out.write(emit_assignment("SEARCH_PATH", include_dir) + "\n")
        if include_dirs:
            out.write("\n")

        for define in defines:
            out.write(emit_assignment("VERILOG_MACRO", define) + "\n")
        if defines:
            out.write("\n")

        for path in files:
            out.write(file_assignment(path) + "\n")

    print(f"include_dirs={len(include_dirs)} defines={len(defines)} files={len(files)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

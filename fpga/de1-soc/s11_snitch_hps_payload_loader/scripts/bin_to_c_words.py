#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib


def parse_args():
    parser = argparse.ArgumentParser(description="Convert a little-endian RV32 binary to a C word header")
    parser.add_argument("binary", type=pathlib.Path)
    parser.add_argument("header", type=pathlib.Path)
    parser.add_argument("--manifest", type=pathlib.Path, required=True)
    parser.add_argument("--source", type=pathlib.Path, required=True)
    parser.add_argument("--dump", type=pathlib.Path, required=True)
    parser.add_argument("--max-words", type=int, required=True)
    return parser.parse_args()


def main():
    args = parse_args()
    data = args.binary.read_bytes()
    if len(data) % 4 != 0:
        data += b"\x00" * (4 - (len(data) % 4))

    words = [
        int.from_bytes(data[i:i + 4], byteorder="little")
        for i in range(0, len(data), 4)
    ]

    if len(words) > args.max_words:
        raise SystemExit(f"payload has {len(words)} words, max is {args.max_words}")

    args.header.parent.mkdir(parents=True, exist_ok=True)
    with args.header.open("w", encoding="utf-8") as f:
        f.write("#ifndef S11_PAYLOAD_WORDS_H\n")
        f.write("#define S11_PAYLOAD_WORDS_H\n\n")
        f.write(f"#define S11_PAYLOAD_WORD_COUNT {len(words)}u\n")
        f.write(f"#define S11_PAYLOAD_MAX_WORDS {args.max_words}u\n\n")
        f.write("static const u32 s11_payload_words[S11_PAYLOAD_WORD_COUNT] = {\n")
        for word in words:
            f.write(f"    0x{word:08x}u,\n")
        f.write("};\n\n")
        f.write("#endif\n")

    manifest = {
        "source": str(args.source),
        "dump": str(args.dump),
        "binary": str(args.binary),
        "header": str(args.header),
        "word_count": len(words),
        "byte_count": len(data),
        "max_words": args.max_words,
        "sha256": hashlib.sha256(data).hexdigest(),
    }
    args.manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

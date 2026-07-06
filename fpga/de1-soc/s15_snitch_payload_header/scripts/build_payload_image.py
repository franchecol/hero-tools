#!/usr/bin/env python3
import argparse
import hashlib
import json
import pathlib


MAGIC = 0x50353153  # ASCII "S15P", little-endian in the image.
VERSION = 1
HEADER_WORDS = 10


def parse_int(text):
    return int(text, 0)


def parse_args():
    parser = argparse.ArgumentParser(description="Build an S15 header + RV32 payload image")
    parser.add_argument("--raw-bin", type=pathlib.Path, required=True)
    parser.add_argument("--image", type=pathlib.Path, required=True)
    parser.add_argument("--manifest", type=pathlib.Path, required=True)
    parser.add_argument("--source", type=pathlib.Path, required=True)
    parser.add_argument("--dump", type=pathlib.Path, required=True)
    parser.add_argument("--max-words", type=int, required=True)
    parser.add_argument("--arg0", type=parse_int, required=True)
    parser.add_argument("--arg1", type=parse_int, required=True)
    return parser.parse_args()


def u32(value):
    return value & 0xffffffff


def main():
    args = parse_args()
    data = args.raw_bin.read_bytes()
    if len(data) % 4 != 0:
        data += b"\x00" * (4 - (len(data) % 4))

    payload_words = [
        int.from_bytes(data[i:i + 4], byteorder="little")
        for i in range(0, len(data), 4)
    ]
    if not payload_words:
        raise SystemExit("payload is empty")
    if len(payload_words) > args.max_words:
        raise SystemExit(f"payload has {len(payload_words)} words, max is {args.max_words}")

    arg0 = u32(args.arg0)
    arg1 = u32(args.arg1)
    expected = u32(arg0 + arg1)
    checksum = u32(sum(payload_words))
    header_words = [
        MAGIC,
        VERSION,
        HEADER_WORDS,
        0,  # flags
        0,  # entry word offset; S13/S15 hardware starts at IMEM word 0.
        len(payload_words),
        arg0,
        arg1,
        expected,
        checksum,
    ]

    image_data = b"".join(word.to_bytes(4, byteorder="little") for word in header_words + payload_words)
    args.image.parent.mkdir(parents=True, exist_ok=True)
    args.image.write_bytes(image_data)

    manifest = {
        "format": "s15-header-v1",
        "magic": f"0x{MAGIC:08x}",
        "version": VERSION,
        "header_words": HEADER_WORDS,
        "flags": 0,
        "entry_word": 0,
        "payload_words": len(payload_words),
        "payload_bytes": len(data),
        "image_bytes": len(image_data),
        "arg0": f"0x{arg0:08x}",
        "arg1": f"0x{arg1:08x}",
        "expected": f"0x{expected:08x}",
        "payload_checksum": f"0x{checksum:08x}",
        "sha256": hashlib.sha256(image_data).hexdigest(),
        "source": str(args.source),
        "raw_binary": str(args.raw_bin),
        "image": str(args.image),
        "dump": str(args.dump),
    }
    args.manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

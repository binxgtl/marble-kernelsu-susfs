#!/usr/bin/env python3
"""Check exact NoMount records extracted by ACK from linked vmlinux.o."""
import argparse
from pathlib import Path


def verify(modinfo: bytes, builtin: str) -> None:
    if not modinfo or not modinfo.endswith(b"\0"):
        raise ValueError("missing or truncated NUL-terminated built-in metadata")
    records = set(modinfo.split(b"\0"))
    for required in (b"nomount.version=20", b"nomount.file=fs/nomount/nomount"):
        if required not in records:
            raise ValueError(f"missing exact post-LTO record: {required.decode()}")
    if "kernel/fs/nomount/nomount.ko" not in builtin.splitlines():
        raise ValueError("NoMount is absent from modules.builtin")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("modinfo", type=Path)
    parser.add_argument("builtin", type=Path)
    args = parser.parse_args()
    verify(args.modinfo.read_bytes(), args.builtin.read_text(encoding="utf-8"))
    print("NoMount v20: exact linked built-in version/file records verified")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Compute the order-independent KMI digest of a Module.symvers file.

Link order can move lines in Module.symvers without changing anything that
matters to a vendor module, so hashing the raw file would produce false
alarms. This hashes the sorted set of exported records instead: a mismatch
means the exported symbol set, a CRC, or an export type actually changed.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import sys


class SymversError(RuntimeError):
    pass


def read_records(path: Path) -> list[str]:
    records: list[str] = []
    seen: set[str] = set()
    for number, line in enumerate(
        path.read_text(encoding="utf-8", errors="replace").splitlines(), start=1
    ):
        if not line.strip():
            continue
        fields = line.split("\t")
        if len(fields) < 4:
            raise SymversError(f"{path}:{number}: expected at least 4 tab-separated fields")
        crc, symbol, _module, export_type = fields[0], fields[1], fields[2], fields[3]
        if not crc.startswith("0x"):
            raise SymversError(f"{path}:{number}: CRC {crc!r} is not hexadecimal")
        if symbol in seen:
            raise SymversError(f"{path}:{number}: duplicate exported symbol {symbol!r}")
        seen.add(symbol)
        records.append(f"{symbol}\t{crc}\t{export_type}")
    if not records:
        raise SymversError(f"{path}: no exported symbols found")
    records.sort()
    return records


def digest_of(records: list[str]) -> str:
    return hashlib.sha256(("\n".join(records) + "\n").encode("utf-8")).hexdigest()


def expected_from_manifest(path: Path) -> tuple[int, str]:
    symbols = None
    canonical = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith("#") or not line.strip():
            continue
        parts = line.split("|")
        if len(parts) != 3:
            continue
        if parts[1] == "symbols":
            symbols = int(parts[2])
        elif parts[1] == "canonical_sha256":
            canonical = parts[2]
    if symbols is None or canonical is None:
        raise SymversError(f"{path}: missing symbols or canonical_sha256 entry")
    return symbols, canonical


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("symvers", type=Path)
    parser.add_argument(
        "--expect-manifest",
        type=Path,
        help="compare against manifests/kmi-baseline.txt and fail on any difference",
    )
    args = parser.parse_args()
    try:
        records = read_records(args.symvers)
        actual = digest_of(records)
        print(f"symbols={len(records)}")
        print(f"canonical_sha256={actual}")
        if args.expect_manifest is None:
            return 0

        symbols, canonical = expected_from_manifest(args.expect_manifest)
        print(f"expected_symbols={symbols}")
        print(f"expected_canonical_sha256={canonical}")
        if len(records) != symbols or actual != canonical:
            print(
                "FAIL: the exported KMI surface changed relative to the frozen M1 "
                "baseline. Diff this Module.symvers against the M1 artifact before "
                "updating manifests/kmi-baseline.txt.",
                file=sys.stderr,
            )
            return 1
        print("KMI surface matches the frozen M1 baseline exactly.")
        return 0
    except (SymversError, OSError, ValueError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

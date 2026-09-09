# M2 stock module CRC gate

M2 is a static compatibility check only. It does not package a boot image, load
a module, connect to a phone, flash a partition, or change the accepted M1
kernel configuration.

## Sanitized input

`scripts/m2-extract-stock-module-manifest.sh` recursively discovers `.ko`
files in a local directory. It uses `modprobe --show-modversions` for required
symbols and `modprobe --show-exports` for provider symbols when available, and
the equivalent libkmod APIs otherwise. It independently parses ELF `__versions`
and validates exported `__ksymtab_*` names against absolute `__crc_*` symbols.
At least five modules are checked before the full scan; every remaining module
is also cross-checked while it is processed.

The extractor writes two JSON files so the established requirement manifest can
remain stable while provider metadata is versioned independently. Together they
contain only:

- module basename;
- vermagic;
- dependency module names;
- required symbol names and their 32-bit CRCs;
- exported provider symbol names and their 32-bit CRCs;
- aggregate module and requirement counts;
- the fixed status `NOT BOOT-PROVEN`.

It contains no module bytes, local paths, device identifiers, timestamps, or
partition data. Duplicate basenames and malformed/unversioned inputs fail
closed. The expected stock vendor set is exactly 356 modules.

Run from the repository root:

```bash
./scripts/m2-extract-stock-module-manifest.sh /path/to/ramdisk_vendor/lib/modules
```

## CI comparison

The separate M2 workflow builds the unchanged, pinned M1 baseline on the VPS,
then performs the lightweight comparison on a GitHub-hosted runner. It consumes
`stock-module-versions.json` plus `stock-module-providers.json`. A required
symbol may be provided by M1 `Module.symvers` or by another stock module in the
complete sanitized set. Kernel exports take precedence. A stock provider is
accepted only when it is the single exporter named by the consumer's normalized
dependency list. A symbol absent from both provider sets is reported under
`missing_symbols`; kernel and stock-provider CRC differences are reported under
`crc_mismatches`. Missing dependency edges, zero export CRCs, and ambiguous
provider choices fail closed and are reported separately.

M2 fails if either list is non-empty. Its report always remains **NOT
BOOT-PROVEN**, including when every static CRC matches. Passing M2 authorizes
integration work, but never substitutes for loading the modules on the phone.

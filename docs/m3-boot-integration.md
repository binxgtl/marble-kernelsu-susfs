# M3 Android boot-image integration

M3 replaces only the kernel payload in a local copy of the stock Android boot
image. It preserves the complete compressed generic ramdisk byte-for-byte and
does not read or modify `vendor_boot`, `dtbo`, `vbmeta`, a slot, or any device.
Stock images remain local and are never committed or uploaded to Actions.

## Proven layout

The audited stock layout is Android boot header v4 with a 4096-byte header page,
raw arm64 kernel, compressed generic ramdisk, and a 4096-byte legacy GKI boot
signature. The separate vendor boot v4 image carries the vendor ramdisk and DTB;
M3 deliberately leaves it unchanged.

The old GKI boot signature covers the old kernel, so the repacker rejects
unusual signature sizes and removes that now-invalid signature. AOSP documents
this legacy boot signature as a VTS integrity check rather than the
device-specific AVB decision made by the bootloader. The output is still marked
`UNSIGNED TEST IMAGE — NOT BOOT-PROVEN — DO NOT FLASH`.

## Accepted stock input

The accepted input is the exact, unmodified `images/boot.img` from the same
fastboot ROM package as the build installed on the device. A live partition dump
is **not** required and is not the preferred input: the packaged image is
byte-defined, hashable ahead of time, and free of any local modification the
installed boot partition may already carry.

For the current target that is the Xiaomi China package `OS3.0.5.0.VMRCNXM`,
SHA-256 `e4df49671a7195b7b2bf1c0a0aaa712625eb385f46d92991ca0fccb1c197d515`. Its
embedded kernel identifies itself as
`5.10.236-android12-9-00003-gfb24cf99ad97-ab14313284`, matching the kernel
recorded for the installed system, which is what makes the package the correct
stock reference. Confirming that the device is actually running this build
remains a read-only preflight step, not an assumption.

If the installed build ever diverges from the package on hand, obtain the
matching package rather than dumping a partition, so that the input stays
reproducible and independently verifiable by hash.

## Local construction

Use the accepted stock boot image described above and the verified M1 `Image`.
From the repository root, run exactly:

```bash
./scripts/m3-build-test-image.sh /path/to/stock-boot.img /path/to/Image
```

This creates:

- `artifacts/m3-local/marble-m3-test-boot.img`
- `artifacts/m3-local/marble-m3-test-boot.json`

The tool accepts only boot header v4/1584, validates the raw arm64 Image magic,
preserves header data and ramdisk bytes, ensures the output fits within the
stock input size, reparses the result, and records hashes without exposing the
kernel command line or other device-specific values.

The scripts target a POSIX shell with a Python 3 interpreter. On Windows, run
them under WSL. They also work under Git Bash, where the interpreter is named
`python` rather than `python3`; `scripts/m3-python.sh` resolves either name and
honours an explicit `PYTHON=/path/to/python3` override. The regression suite
additionally needs real symlink and hard-link support, which under Git Bash
means `MSYS=winsymlinks:nativestrict` and Windows Developer Mode.

## Size and AVB accounting

The stock package image is partition-sized and carries an AVB hash footer. These
are distinct numbers and are reported separately rather than collapsed into one:

| Quantity | Value | Meaning |
|---|---|---|
| Stock file / partition-sized image | 201326592 bytes | Size of `images/boot.img`, equal to the declared `boot_a` and `boot_b` partition size of 196608 KB |
| AVB `original_image_size` | 48246784 bytes | Real boot payload: header page, kernel, ramdisk, and the 4096-byte GKI boot signature |
| AVB vbmeta offset | 48246784 | Start of the 896-byte vbmeta struct that the footer points at |
| AVB vbmeta size | 896 bytes | Size of that vbmeta struct |
| AVB footer | last 64 bytes, offset 201326528 | `AVBf` footer describing the two values above |
| Generated test image | 39792640 bytes with the M1 `Image` from run #33 | 4096-byte header page plus the page-aligned kernel and ramdisk |

The repacker's upper bound is the stock file size, and because that file is
exactly partition-sized, the bound is a real partition-capacity check rather
than an artefact of padding. It is a conservative outer limit, not a statement
about the payload: an output can satisfy it and still be far larger than the
stock payload.

The generated image deliberately contains no boot signature, no vbmeta struct,
and no AVB footer. Everything after the page-aligned ramdisk is dropped, which
is why the output is labelled unsigned and test-only.

**Whether the device's bootloader accepts a download of this size over fastboot
is unproven.** No download-buffer capacity has been measured on this hardware,
and a refusal is an expected and acceptable outcome. See
[`recovery.md`](recovery.md) for the abort rules.

## CI boundary

CI uses only synthetic boot, kernel, ramdisk, and signature bytes. Regression
tests cover a successful byte-preserving repack plus invalid magic, wrong header
version, invalid signature size, invalid kernel format, oversized output,
direct/symlink/hard-link path collisions, and Python interpreter resolution. No
real boot image or vendor module is present in the workflow or its artifacts.

## Hardware gate

Status remains **HARDWARE TEST PENDING**. After checking the JSON report and its
SHA-256 value, the only permitted first test is a non-writing temporary boot:

```bash
fastboot boot artifacts/m3-local/marble-m3-test-boot.img
```

If temporary boot is unsupported or rejected, stop; do not substitute any
`fastboot flash` command. If Android boots, return `uname -a`, `/proc/version`,
`/proc/modules`, the boot-completed property, and a complete privileged dmesg.
Powering off or rebooting returns to the unchanged installed stock slot.

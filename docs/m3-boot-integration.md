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

## Local construction

Use a known-good stock `boot` partition dump from the same installed build and
the verified M1 `Image`. From the repository root, run exactly:

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

## CI boundary

CI uses only synthetic boot, kernel, ramdisk, and signature bytes. Regression
tests cover a successful byte-preserving repack plus invalid magic, wrong header
version, invalid signature size, invalid kernel format, oversized output, and
direct/symlink/hard-link path collisions. No real boot image or vendor module is
present in the workflow or its artifacts.

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

# Recovery policy

M0/M1 is build-only and cannot modify a phone. The CI and project scripts must
not contain `fastboot flash`, partition-writing `dd`, repartitioning commands,
or AVB-state changes.

M3 introduces the first device-side action in this project, so the expansion
that the earlier revision of this document deferred is written out below. It
covers exactly one permitted operation: a single ephemeral, non-writing
`fastboot boot`. Nothing here authorizes an internal storage layout change.

## Stock image provenance

| Fact | Value |
|---|---|
| ROM package | Xiaomi China fastboot package `OS3.0.5.0.VMRCNXM` (`marble.cn.1.1.0152`) |
| Device | `marble` (Redmi Note 12 Turbo, Qualcomm SM7475) |
| Reference image | `images/boot.img` from that unmodified package |
| SHA-256 | `e4df49671a7195b7b2bf1c0a0aaa712625eb385f46d92991ca0fccb1c197d515` |
| Size | 201326592 bytes, equal to the `boot_a`/`boot_b` partition size |
| Contained kernel | `5.10.236-android12-9-00003-gfb24cf99ad97-ab14313284` |

That kernel identity is the same string the runtime audit recorded for the
installed system, which is why this package is treated as the matching stock
reference. The image itself is kept outside Git and is never uploaded to
Actions. It is only ever opened read-only; the repacker writes a separate output
file and refuses any argument combination that would resolve onto an input.

The recorded generic ramdisk in this package is the clean GKI ramdisk. The
installed device ramdisk was audited separately and contains a KernelSU wrapper
in front of Android init, so an ephemeral boot from a repacked package image
runs stock init instead. That difference is intended and is not a fault.

## The only permitted device operation

```bash
fastboot boot artifacts/m3-local/marble-m3-test-boot.img
```

`fastboot boot` downloads the image to memory and boots it once. It writes no
partition, changes no slot, and leaves AVB metadata untouched.

## Prohibited at this gate

- `fastboot flash` of any partition, including `boot`, `vendor_boot`, `dtbo`,
  `vbmeta`, and `vbmeta_system`.
- `fastboot set_active`, `--set-active`, or any other slot change.
- `fastboot --disable-verity`, `--disable-verification`, any vbmeta or AVB state
  modification, and any bootloader lock or unlock transition.
- `fastboot erase`, `fastboot wipe`, repartitioning, GPT edits, and
  partition-writing `dd`.
- Substituting a flash for a refused temporary boot.

## Abort conditions

Stop immediately, change nothing, and report the exact message if any of the
following happens:

- the bootloader rejects or does not implement `fastboot boot`;
- the download is refused for size or buffer reasons;
- the device reports a verification, signature, or AVB failure;
- the device is not detected in fastboot mode, or it enumerates as a different
  device than expected;
- anything at all prompts for a flash, a slot switch, or a lock-state change.

A refusal is a valid, informative result. It is never a reason to escalate to a
writing command.

## Executed record

The gate ran on 2026-09-10. `fastboot boot` was issued once against the verified
test image; no other fastboot subcommand was used. The device booted, was
observed, and was returned to the installed system with a normal reboot, which
came back on the stock kernel with all 419 modules. Nothing was written.

An earlier attempt the same day did not reach `sys.boot_completed`, but the
cause was traced to a pre-existing userspace fault unrelated to the kernel:
`DeviceLockController` had been uninstalled for user 0, so `system_server`
crash-looped on `DEVICE_LOCK_CONTROLLER_SERVICE not found`. The stock kernel
failed identically until the package was restored with
`pm install-existing --user 0`, which confirms the fault was not caused by the
test image. This is a reminder that the gate needs a device that boots stock
cleanly first; otherwise the result is uninterpretable.

## Rollback

An ephemeral `fastboot boot` leaves storage untouched, so rollback is simply a
normal reboot into the installed system:

- If the test kernel boots, collect the required evidence and then reboot
  normally. The device returns to the unchanged installed slot.
- If the test kernel hangs, panics, or shows no display, force a reboot with the
  hardware key combination or let the battery-backed watchdog restart the
  device. Because nothing was written, the next boot uses the untouched stock
  `boot` partition.
- No stock image needs to be re-flashed to recover from this operation. Keeping
  the verified `OS3.0.5.0.VMRCNXM` package available locally is nonetheless
  worthwhile as a defence against unrelated accidents.

## Still required before any writing milestone

A later milestone that writes to a partition must extend this document again
with current slot handling for that specific write, a verified restore image per
target partition, and a rehearsed recovery path. That expansion is not part of
M3.

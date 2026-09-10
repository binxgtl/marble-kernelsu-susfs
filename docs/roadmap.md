# Roadmap

This file is the long-term source of truth for what this project is doing and
what comes next. A new session should be able to read this file plus
[`bringup.md`](bringup.md) and know the current state without any outside
context.

Milestone IDs are stable. Once an ID is assigned it is never reused for
something else and the list is never renumbered, even if a milestone is dropped
or split. If work turns out not to fit an existing ID, append a new one at the
end rather than shifting the others.

## Status

| ID | Milestone | Status |
|---|---|---|
| M0 | Repository and reproducible CI | **DONE** |
| M1 | Clean ACK 5.10.236 GKI baseline | **DONE** |
| M2 | Stock vendor-module KMI compatibility | **DONE** |
| M3 | HyperOS hardware boot with the custom ACK kernel | **DONE** |
| M4 | KernelSU Next source integration | **CURRENT** |
| M5 | Native initramfs boot | Not started |
| M6 | UFS, firmware and remoteproc bring-up | Not started |
| M7 | DRM display and touch | Not started |
| M8 | USB host and battery/power basics | Not started |
| M9 | Native GPU / Turnip | Not started |
| M10 | Native rootfs and systemd | Not started |
| M11 | Audio | Not started |
| M12 | Wi-Fi | Not started |
| M13 | Bluetooth | Not started |
| M14 | Bluetooth HFP/SCO | Not started |
| M15 | Charging and USB-PD integration | Not started |
| M16 | Suspend/resume | Not started |
| M17 | Dual-boot UX / selector | Not started |
| M18 | Performance and polish | Not started |

A milestone changes status only when its exit criteria are met, or when a
decision to stop or change course is written down here with its reasoning.
Nothing moves to DONE on the strength of a conversation.

## Standing rules

- **The M3 hardware-proven kernel is the control baseline.** Every later
  milestone is measured against it. If something regresses, the question is
  what changed relative to M3, so M3's inputs stay pinned and reproducible.
- **M4 is KernelSU Next source integration only.** SUSFS does not automatically
  become the next milestone. It needs its own ID and its own approval when and
  if it is wanted.
- **M5 is where real native Linux begins.** Everything before it runs Android
  userspace.
- **No skipping ahead.** GPU, audio and Wi-Fi work does not start before the
  lower prerequisites are met. A milestone that depends on storage or display
  cannot be validated without them.
- **When a milestone starts, [`bringup.md`](bringup.md) gets the detailed gate
  and the evidence.** This file stays a map; `bringup.md` carries the proof.
- **No forcing voltage or current, and no bypassing thermal or battery
  protection**, at any milestone.
- **Device-write policy is unchanged.** No `flash`, `erase`, `format`,
  `set_active`, bootloader lock or unlock, vbmeta/AVB modification, or
  repartitioning, unless a dedicated milestone authorising it has been approved
  first. Ephemeral `fastboot boot` remains the only sanctioned device
  operation. See [`recovery.md`](recovery.md).

## Superseded milestone numbering

Earlier revisions of `hardware-matrix.md` and `assumptions.md` used a different,
looser numbering that predates this file. Those references have been updated to
the IDs above. For anyone reading old commits or old notes:

| Old ID | Meaning | Current ID |
|---|---|---|
| M8 | Touch input | M7 |
| M9 | USB host peripherals | M8 |
| M10 | Battery telemetry | M8 |
| M11 | Native GPU acceleration | M9 |
| M13 | Audio bring-up | M11 |
| M14 | Wi-Fi | M12 |
| M15 | Bluetooth | M13 |
| M16 | Bluetooth HFP/SCO | M14 |
| M17 | Fast charging | M15 |
| M19 | Dual-boot selector | M17 |

M0–M3, M6 and M7 kept their numbers.

---

## M0 — Repository and reproducible CI

**Goal.** A private repository whose inputs are pinned and whose CI is
reproducible, with no device operations anywhere in the pipeline.

**Prerequisites.** None.

**Scope.** Repository layout, pinned source and toolchain manifests, hosted CI
on `ubuntu-24.04`, sanitised audit documentation, artifact hygiene.

**Exit criteria.** Source and toolchain identity checks pass; CI is green; no
proprietary payload is present in the checkout or in any artifact.

**Explicitly out of scope.** Any device operation; any proprietary blob in Git.

**Status: DONE.**

## M1 — Clean ACK 5.10.236 GKI baseline

**Goal.** Build an unmodified Android Common Kernel GKI arm64 image from a
pinned commit with a pinned toolchain.

**Prerequisites.** M0.

**Scope.** ACK commit `b97c62c4e7d1e80fb6a2cb0cb381f03bbcd26a4e`, clang
`r416183b`, `gki_defconfig` plus `configs/baseline.fragment`. Produces `Image`,
`Image.lz4`, `config`, `System.map`, `Module.symvers`, hashes and metadata.

**Exit criteria.** The baseline job is green and the artifact is reproducible
from the locked revisions.

**Explicitly out of scope.** Vendor patches, device trees, packaging, booting.

**Status: DONE.** Reproducibility is demonstrated, not assumed: two independent
runs produced `image_sha256=15b59c1353825516c415fbedfb98593f01cdf997f848e542b0a6bb98b7e52353`.

## M2 — Stock vendor-module KMI compatibility

**Goal.** Prove statically that the clean baseline satisfies every stock
vendor-module symbol requirement.

**Prerequisites.** M1.

**Scope.** Sanitised extraction of module metadata on a trusted local machine;
provider-aware comparison of every required symbol and CRC against the
unmodified M1 `Module.symvers`.

**Exit criteria.** Every requirement resolves with an exact CRC match; missing
symbols and CRC mismatches are reported separately and either fails the gate.

**Explicitly out of scope.** Boot-image packaging; any device test. A green
static gate is explicitly **not** proof of bootability.

**Status: DONE.**

## M3 — HyperOS hardware boot with the custom ACK kernel

**Goal.** Boot the stock Android userspace on the clean ACK kernel, without
writing anything to the device.

**Prerequisites.** M1, M2.

**Scope.** Replace only the kernel payload in a local copy of the stock boot v4
image, preserving the generic ramdisk byte-for-byte; validate the result; boot
it once with `fastboot boot`.

**Exit criteria.** Synthetic CI green, and the image boots to
`sys.boot_completed=1` with stock vendor modules loading cleanly.

**Explicitly out of scope.** Any partition write; `vendor_boot`, `dtbo` or
`vbmeta` changes; slot changes.

**Status: DONE (2026-09-10).** `sys.boot_completed=1` at 31 s, 418 of 419
modules loaded, zero unknown-symbol/version-magic/CRC errors, zero system
crashes. Full evidence in [`m3-boot-integration.md`](m3-boot-integration.md).

## M4 — KernelSU Next source integration

**Goal.** Compile KernelSU Next into the M3-proven kernel source, changing
nothing else.

**Prerequisites.** M3.

**Scope.** Pin KernelSU Next by tag and commit; integrate it into the ACK tree;
keep the configuration delta to what KernelSU genuinely requires; keep the KMI
surface frozen; produce a test image through the existing M3 pipeline.

**Exit criteria.** CI builds green with a deterministic in-tree KernelSU
version; the frozen KMI digest is unchanged; the provider-aware gate still
passes; the resulting image boots the device and root works.

**Explicitly out of scope.** SUSFS. Any LTO, CFI or shadow-call-stack change.
Any change to the M1 baseline output. Any partition write.

**Status: CURRENT.** Details in [`m4-kernelsu.md`](m4-kernelsu.md).

## M5 — Native initramfs boot

**Goal.** Boot bootloader → Linux kernel → a native initramfs with a native
PID 1, with no Android framework or userspace involved.

**Prerequisites.** M3. M4 is not required; the control baseline is M3.

**Scope.** A minimal initramfs with a real init, a shell on some reachable
console, and enough kernel configuration to reach it. Establishing how the
device is booted into this image without writing a partition.

**Exit criteria.** An interactive shell from a native initramfs on the device,
reached by a non-writing boot, with the kernel log captured.

**Explicitly out of scope.** Persistent storage as root, display, GPU, audio,
networking, systemd. Anything that needs a real rootfs.

## M6 — UFS, firmware and remoteproc bring-up

**Goal.** Reach the storage and firmware foundation the rest of the native
stack depends on.

**Prerequisites.** M5.

**Scope.** UFS storage path usable from native Linux; firmware staging and
loading; ADSP, CDSP, MSS and SLPI remoteproc bring-up and their load ordering.

**Exit criteria.** Storage is readable and writable from the native initramfs;
the remoteprocs required by later milestones come up, with the sequencing
documented.

**Explicitly out of scope.** Repartitioning or reformatting internal storage.
Display, GPU, audio, networking.

## M7 — DRM display and touch

**Goal.** A working native display and touch input.

**Prerequisites.** M6.

**Scope.** Native DRM/KMS at 1080x2400 at 60 Hz first; Goodix touch working
natively with correct coordinates and orientation.

**Exit criteria.** A stable 60 Hz native mode set, and touch events with
correct geometry through the standard input stack.

**Explicitly out of scope.** Higher refresh rates, GPU acceleration, panel
power tuning.

## M8 — USB host and battery/power basics

**Goal.** Basic USB and basic power visibility.

**Prerequisites.** M6.

**Scope.** USB host and device modes; battery reporting; Type-C and
power-supply plumbing.

**Exit criteria.** A USB keyboard, mouse and mass-storage device work in host
mode; battery state is reported correctly.

**Explicitly out of scope.** Fast charging and USB-PD negotiation, which are
M15. No forcing current or voltage, and no bypassing protection.

## M9 — Native GPU / Turnip

**Goal.** Native GPU acceleration without Android or a chroot.

**Prerequisites.** M7.

**Scope.** Adreno 725 native render node; Mesa with Turnip; a render test that
does not depend on Android userspace.

**Exit criteria.** A successful native render test against the native render
node, with no Android or chroot component.

**Explicitly out of scope.** Performance tuning, overclocking, thermal policy
changes.

## M10 — Native rootfs and systemd

**Goal.** Boot a real native root filesystem with systemd as PID 1.

**Prerequisites.** M6. M7 is strongly advisable so the result is usable.

**Scope.** A real Linux root filesystem, systemd as PID 1, a stable Linux
userspace.

**Exit criteria.** The device boots to a systemd userspace with no Android
framework, and it survives reboots.

**Explicitly out of scope.** Repartitioning internal storage. Android
`/data` decryption. Anything requiring Android key handling.

## M11 — Audio

**Goal.** Basic native audio in and out.

**Prerequisites.** M6, M10.

**Scope.** ALSA and PipeWire playback and capture, with conservative routing
and gain.

**Exit criteria.** Speaker playback and microphone capture work natively at
safe levels.

**Explicitly out of scope.** Bluetooth audio, which is M13 and M14. Gain
limits that exceed what stock uses.

## M12 — Wi-Fi

**Goal.** Native Wi-Fi networking.

**Prerequisites.** M6, M10.

**Scope.** QCA6490 firmware and module bring-up, plus native userspace
networking.

**Exit criteria.** Scan, WPA2 and WPA3 association, and reliable reconnection.

**Explicitly out of scope.** Bluetooth coexistence tuning, throughput
optimisation.

## M13 — Bluetooth

**Goal.** Native Bluetooth.

**Prerequisites.** M6, M10.

**Scope.** Qualcomm Bluetooth transport with BlueZ.

**Exit criteria.** `hci0` present and unblocked; pairing, reconnection, HID and
A2DP all work.

**Explicitly out of scope.** HFP and SCO voice, which is M14.

## M14 — Bluetooth HFP/SCO

**Goal.** Bluetooth voice audio.

**Prerequisites.** M11, M13.

**Scope.** The HFP and SCO voice path through BlueZ and PipeWire.

**Exit criteria.** A two-way voice call over a Bluetooth headset with usable
audio in both directions.

**Explicitly out of scope.** Codec tuning beyond what is needed to work.

## M15 — Charging and USB-PD integration

**Goal.** Correct, safe charging including negotiated fast charging.

**Prerequisites.** M8.

**Scope.** Charging state reporting; USB-PD and PPS negotiation; instrumenting
the negotiated profile and the thermal and current limits.

**Exit criteria.** Charging reports correctly, and PD/PPS negotiation matches
what stock negotiates with the same charger and cable.

**Explicitly out of scope.** Forcing voltage or current, exceeding stock
limits, or bypassing thermal or battery protection. This is a hard safety
boundary, not a preference.

## M16 — Suspend/resume

**Goal.** Reliable suspend and resume.

**Prerequisites.** M10, and whichever of M7, M8, M12 and M13 are in use.

**Scope.** Suspend and resume without serious regressions in storage, display,
input or networking.

**Exit criteria.** Repeated suspend/resume cycles with no loss of storage,
display, input or network function, and no wakeup failures.

**Explicitly out of scope.** Deep power optimisation, which is M18.

## M17 — Dual-boot UX / selector

**Goal.** A way to choose between Android and native Linux, with a clear
rollback.

**Prerequisites.** M10, M16. Both Android and the native path must each boot
reliably on their own first.

**Scope.** Designing and implementing the selector, with Android as the default
and as the failure fallback.

**Exit criteria.** The selector chooses either system reliably, and a failed
native boot falls back to Android without user intervention.

**Explicitly out of scope.** Anything that writes partitions or changes AVB
state without a separately approved decision. This milestone is likely to need
one; it must be written down before any such action.

## M18 — Performance and polish

**Goal.** Make the result pleasant and maintainable.

**Prerequisites.** M10, M16.

**Scope.** Power and performance tuning, boot time, reliability, packaging and
documentation.

**Exit criteria.** Documented, reproducible packaging and a stated performance
and reliability baseline.

**Explicitly out of scope.** Overclocking, thermal policy bypass, or any
tuning that trades safety for numbers.

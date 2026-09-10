# Assumptions and unresolved facts

Every item here is deliberately not treated as established fact.

| ID | Assumption or question | Evidence available | How to resolve | Gate |
|---|---|---|---|---|
| A-001 | ~~The clean ACK 5.10.236 GKI output can satisfy every stock vendor-module KMI dependency~~ **PROVEN 2026-09-10** | Static CRC comparison passed at M2, then confirmed on hardware: 418 of 419 stock modules loaded under the clean ACK kernel with zero unknown-symbol, version-magic, or CRC errors. The one absent module was the stock ramdisk's out-of-tree `kernelsu` LKM, which this configuration deliberately does not carry | Resolved; no further action | M2/M3 |
| A-002 | `android12-5.10-2025-05_r1` is the closest public source ancestor of the running vendor kernel | It is Linux 5.10.236, matching runtime base version; runtime carries an additional Android/vendor suffix | Boot behavior and vendor patch provenance analysis | M3+ |
| A-003 | Xiaomi `marble-s-oss` kernel and device-tree heads are suitable donors | Official branches exist, but they are Android S-era and older than runtime | Review and port only required subsystem commits with citations | M3+ |
| A-004 | KGSL plus Turnip can be retained for the first native graphics path | Android exposes KGSL and supplied chroot evidence reports Turnip; native boot is not tested | Native rootfs render test | M11 |
| A-005 | The supplied firmware inventory is sufficient for native remoteproc/WLAN/BT | Names and Android runtime states were observed; dependencies and load order are incomplete | Trace firmware requests and remoteproc sequencing | M6/M14/M15 |
| A-006 | Xiaomi 67 W charging is available outside Android userspace | PD/PPS capabilities and Qualcomm/Xiaomi charger modules exist; authentication/policy dependencies are unknown | Instrument negotiated profiles and thermal/current limits with stock charger/cable | M17 |
| A-007 | A volume-key selector can be implemented before Android init while retaining safe fallback | GPIO/PMIC key inputs exist after kernel bring-up; bootloader timing/path is unknown | Prototype only after both independent paths are stable | M19 |
| A-008 | ThinLTO is an acceptable M1 CI variation when the audit does not identify the stock LTO mode | **Fact question resolved, then tested.** The stock config sets `CONFIG_LTO_CLANG_FULL=y` with `CONFIG_LTO_CLANG_THIN` unset, while M1 run #33 records `lto_mode=thin`. That ThinLTO build booted HyperOS on 2026-09-10 with every stock vendor module loaded, so the divergence does not block boot | Treat as a known, accepted runtime variable rather than an open question. Revisit only if a later milestone shows LTO-mode-dependent behaviour | M2/M3 |

## Recovering the stock kernel config without a device

A-008 previously expected `/proc/config.gz` from a running device. That is not
required. The stock GKI kernel is built with `CONFIG_IKCONFIG=y`, so its own
`.config` is embedded in the raw `Image` inside the stock boot image and can be
read locally, read-only, from the ROM package alone:

1. Parse the boot header for `kernel_size` and read the kernel at offset 4096.
2. Locate the `IKCFG_ST` and `IKCFG_ED` markers in those bytes.
3. Gunzip everything between them.

For `OS3.0.5.0.VMRCNXM` this yields a 181361-character config that also confirms
`CONFIG_IKCONFIG_PROC=y`, `CONFIG_CFI_CLANG=y`, `CONFIG_SHADOW_CALL_STACK=y`,
`CONFIG_MODVERSIONS=y`, `CONFIG_PREEMPT=y`, and `CONFIG_HZ=250`. Reading
`/proc/config.gz` on the device would only re-confirm the same file and is
therefore an optional cross-check, not a gate input.

## Explicit non-assumptions

- A module's vermagic alone does not prove KMI compatibility.
- Installed-but-inactive touch/audio/network modules do not identify the active
  hardware path.
- Partition dump sizes are not boot payload sizes.
- The active slot from one audit is not a permanent target slot.
- A native rootfs cannot assume Android userdata decryption services.

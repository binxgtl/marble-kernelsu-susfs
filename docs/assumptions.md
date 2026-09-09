# Assumptions and unresolved facts

Every item here is deliberately not treated as established fact.

| ID | Assumption or question | Evidence available | How to resolve | Gate |
|---|---|---|---|---|
| A-001 | The clean ACK 5.10.236 GKI output can satisfy every stock vendor-module KMI dependency | All 356 audited modules use a 5.10.160 GKI vermagic with MODVERSIONS; ACK tag includes Qualcomm/Xiaomi KMI symbol lists | Compare every module-required symbol CRC against the built `Module.symvers`, then device load test | M2/M3 |
| A-002 | `android12-5.10-2025-05_r1` is the closest public source ancestor of the running vendor kernel | It is Linux 5.10.236, matching runtime base version; runtime carries an additional Android/vendor suffix | Boot behavior and vendor patch provenance analysis | M3+ |
| A-003 | Xiaomi `marble-s-oss` kernel and device-tree heads are suitable donors | Official branches exist, but they are Android S-era and older than runtime | Review and port only required subsystem commits with citations | M3+ |
| A-004 | KGSL plus Turnip can be retained for the first native graphics path | Android exposes KGSL and supplied chroot evidence reports Turnip; native boot is not tested | Native rootfs render test | M11 |
| A-005 | The supplied firmware inventory is sufficient for native remoteproc/WLAN/BT | Names and Android runtime states were observed; dependencies and load order are incomplete | Trace firmware requests and remoteproc sequencing | M6/M14/M15 |
| A-006 | Xiaomi 67 W charging is available outside Android userspace | PD/PPS capabilities and Qualcomm/Xiaomi charger modules exist; authentication/policy dependencies are unknown | Instrument negotiated profiles and thermal/current limits with stock charger/cable | M17 |
| A-007 | A volume-key selector can be implemented before Android init while retaining safe fallback | GPIO/PMIC key inputs exist after kernel bring-up; bootloader timing/path is unknown | Prototype only after both independent paths are stable | M19 |
| A-008 | Current GitHub-hosted runner capacity is sufficient for the full pinned build | Account plan does not define per-job hardware | CI records `lscpu`, RAM, and disk; adjust job only from observed data | M0/M1 |

## Explicit non-assumptions

- A module's vermagic alone does not prove KMI compatibility.
- Installed-but-inactive touch/audio/network modules do not identify the active
  hardware path.
- Partition dump sizes are not boot payload sizes.
- The active slot from one audit is not a permanent target slot.
- A native rootfs cannot assume Android userdata decryption services.

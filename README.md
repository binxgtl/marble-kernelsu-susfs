# marble-native-linux

Reproducible kernel and platform bring-up for the Redmi Note 12 Turbo
(`marble`, Qualcomm SM7475).

## Current gate

M0/M1 is accepted and M2 static KMI verification is green. M3 is now in scope:

- M0: private repository, pinned sources, reproducible CI, sanitized audit docs.
- M1: clean Android Common Kernel (ACK) 5.10.236 GKI arm64 build.
- M2: sanitized stock-module symbol/CRC comparison against the unchanged M1
  `Module.symvers`.
- M3: local-only boot v4 kernel replacement with synthetic CI validation and a
  non-writing physical boot gate.

The current work deliberately does **not** include Xiaomi hardware forward-ports,
KernelSU, native-Linux hardware work, a dual-boot selector, performance tuning,
flashing, AVB changes, or partition changes.

## Source baseline

The candidate `android12-5.10-2025-05_r1` resolves to ACK commit
`b97c62c4e7d1e80fb6a2cb0cb381f03bbcd26a4e` and identifies itself as Linux
5.10.236. Exact source and toolchain revisions are recorded in
[`manifests/sources.lock`](manifests/sources.lock).

## Build locally

The scripts only fetch public source/toolchain content and compile. They never
touch a phone.

```bash
scripts/fetch-sources.sh work
scripts/setup-toolchain.sh work
scripts/build-kernel.sh work artifacts
scripts/verify-kmi.sh artifacts/config manifests/vendor-module-metadata.tsv artifacts/Module.symvers
```

The build output is written under `artifacts/`. CI additionally records runner
CPU, RAM, and disk facts instead of assuming a larger runner from the account
plan. The M1 CI fragment selects ThinLTO because the supplied audit confirms
Clang LTO but does not distinguish Full from Thin, and the observed 2-vCPU
runner was terminated while linking the Full-LTO GKI. The selected mode is
recorded in `build-metadata.txt`; exact stock-mode matching remains an M2/M3
input gate.

## Safety and privacy

Uploaded audit bundles, boot images, vendor boot images, DTBO/VBMeta images,
firmware, and vendor modules are never committed or uploaded as CI artifacts.
Only sanitized technical facts and hashes are retained here.

See [`docs/bringup.md`](docs/bringup.md) for milestone gates and
[`docs/assumptions.md`](docs/assumptions.md) for facts that are not yet proven.
M2 extraction and report semantics are documented in
[`docs/m2-kmi.md`](docs/m2-kmi.md).
M3 local packaging and its hardware gate are documented in
[`docs/m3-boot-integration.md`](docs/m3-boot-integration.md).

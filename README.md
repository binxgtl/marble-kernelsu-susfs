# marble-native-linux

Reproducible kernel and platform bring-up for the Redmi Note 12 Turbo
(`marble`, Qualcomm SM7475).

## Current gate

Only M0/M1 is in scope:

- M0: private repository, pinned sources, reproducible CI, sanitized audit docs.
- M1: clean Android Common Kernel (ACK) 5.10.236 GKI arm64 build.

The baseline deliberately does **not** include Xiaomi hardware forward-ports,
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
scripts/verify-kmi.sh artifacts/.config manifests/vendor-module-metadata.tsv artifacts/Module.symvers
```

The build output is written under `artifacts/`. CI additionally records runner
CPU, RAM, and disk facts instead of assuming a larger runner from the account
plan.

## Safety and privacy

Uploaded audit bundles, boot images, vendor boot images, DTBO/VBMeta images,
firmware, and vendor modules are never committed or uploaded as CI artifacts.
Only sanitized technical facts and hashes are retained here.

See [`docs/bringup.md`](docs/bringup.md) for milestone gates and
[`docs/assumptions.md`](docs/assumptions.md) for facts that are not yet proven.

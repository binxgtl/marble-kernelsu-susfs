# marble KernelSU Next + SUSFS + NoMount

An independent source-only kernel project for Redmi Note 12 Turbo / POCO F5
(marble), forked from the completed M4 integration in `binxgtl/marble-native-linux`.
It does not change that project's M9/M10 work or frozen candidates.

The baseline remains ACK **5.10.236**, commit
`b97c62c4e7d1e80fb6a2cb0cb381f03bbcd26a4e`, with pinned Android clang r416183b,
CFI, shadow call stack and module versioning. This project deliberately uses
**Full LTO on GitHub-hosted Actions**, as requested by the operator.

The first feature set is:
- KernelSU Next with upstream SUSFS integration, pinned to the WildKernels r21
  root commit `4c5853188012f63a1a1fedd4a57fda6375fecb38` (v3.4.0).
- SUSFS **v2.3.0**, exact operator pin
  `9892175b4acec7ee844e113b8d02c0f4d12cdfac`.
- NoMount built-in **version 20**, pinned to
  `5a610db7649a59eb3e3d710653618d594941f8da`.

This is a root-source upgrade from historical M4's KSU Next v3.3.0, not merely
an unchanged-M4 build with one configuration flag. See
[the engineering record](docs/susfs-nomount.md) and
[the immutable feature lock](manifests/features.lock.json).

## Gates

The dedicated Actions workflow checks integration/tests, builds on
`ubuntu-24.04`, and requires the original frozen exported KMI digest plus the
provider-aware stock-module comparison. Full LTO does not authorize disabling
CFI, SCS, MODVERSIONS or vendor CRC checks.

Only public source-derived outputs go to CI. Real Android boot images are
assembled locally from the canonical ROM after a successful build. No AnyKernel
installer or automated device/partition-writing workflow is included.
NoMount's userspace package and SUSFS's control tool are separate from the kernel.
Building them does not authorize installing modules or setting hiding rules.

**Status: The corrected Full LTO workflow passed all jobs, and its nondirty
kernel booted both temporarily and after installation to `boot_a` on
2026-10-06.** The installed release is `5.10.236-gb97c62c4e7d1`; its exact
tested boot SHA256 is `17ded6d89e641725791a1ac237b8aa18f9bf518e26105890f0d94bef71cd39c2`.
All 18,368 provider-aware stock-module KMI requirements matched. See the
[nondirty installation record](docs/nondirty-install-2026-10-06.md).

The prior kernel was also boot-tested and installed on 2026-10-04; its Manager
reported KernelSU Next v3.4.0 built-in Working and SUSFS v2.3.0 Supported.
The [earlier test record](docs/boot-test-2026-10-04.md) preserves its evidence
and first CI run's failure. The current installation does not establish
long-term stability, root shell through ADB, NoMount redirection or SUSFS
hiding behavior. Future hardware operations require a fresh exact-image request.

Historical M4 source and records are retained for provenance. Its old workflows
are archived in `docs/historical-ci/`, so they cannot run accidentally here.

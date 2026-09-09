# Bring-up gates

## M0 — repository and reproducible CI

- Private repository; `main` remains known-good.
- Work lands through `bringup/m0-m1` and a pull request.
- Public inputs are pinned by immutable commit SHA.
- CI uses `ubuntu-24.04`, records actual runner resources, and cancels superseded
  builds on the same ref.
- CI performs no device operations and receives no stock images/modules.
- Artifacts contain only redistributable build outputs and reports.

Exit: source/toolchain identity checks and repository verification pass.

## M1 — clean baseline kernel build

- Build ACK commit `b97c62c4e7d1e80fb6a2cb0cb381f03bbcd26a4e`.
- Confirm kernel base version 5.10.236.
- Use pinned clang-r416183b.
- Preserve PREEMPT, HZ=250, IKCONFIG, UCLAMP, cgroups/memcg, BPF/JIT,
  KALLSYMS, energy model, CPU frequency, modules/unload/MODVERSIONS, LTO,
  Clang CFI, and shadow-call-stack.
- Produce `Image`, `Image.lz4`, `.config`, `System.map`, `Module.symvers`, hashes,
  and build/runner metadata.

Exit: the GitHub Actions baseline job is green and its artifact is reproducible
from the locked revisions.

## M2 boundary

M1's CI check is static because proprietary vendor modules are intentionally not
uploaded. M2 requires local analysis of the user's module directory against the
M1 `Module.symvers`, followed by a device-side load/boot test. Until then, the
compatibility result must say **not proven**.

## Prohibited before later gates

No flashing, repartitioning, AVB-state changes, KernelSU integration,
hardware-forward-port patches, dual-boot selector, overclocking, or thermal
policy bypass is part of M0/M1.

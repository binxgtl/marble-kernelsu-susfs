# Bring-up gates

This file carries the detailed gate and the collected evidence for milestones
that have started. [`roadmap.md`](roadmap.md) is the source of truth for the
full milestone list, their IDs, and what comes next; a milestone gets a section
here when its implementation begins.

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

## M2 — stock module CRC compatibility

- Extract only sanitized module basenames, vermagic, dependencies, required
  symbols, and `__versions` CRCs on a trusted local machine.
- Cross-check kmod output against independent ELF parsing before processing the
  complete stock set.
- Compare every requirement with the unchanged M1 `Module.symvers`.
- Report missing symbols independently from CRC mismatches and fail on either.
- Keep the result **NOT BOOT-PROVEN**, even when the static CRC gate passes.

Exit: all stock requirements exist with exact CRC matches in the separate M2
workflow. No boot-image packaging or device test occurs in M2.

## M3 — Android boot integration

- Accept only an audited Android boot header v4 input kept outside Git.
- Replace only the raw kernel; preserve the compressed generic ramdisk exactly.
- Remove the stale legacy GKI signature and label the result unsigned/test-only.
- Reparse the output, enforce its size boundary, and record sanitized hashes.
- Exercise success and fail-closed cases using synthetic inputs in hosted CI.
- Do not write a partition; the first device gate is temporary boot only.

Exit: synthetic CI is green and the locally generated image passes a physical,
non-writing boot test.

**Met on 2026-09-10.** The repacked image temporarily booted HyperOS to
`sys.boot_completed=1` at 31 s with 418 of 419 stock modules loaded, no
unknown-symbol or CRC errors, and no system-process crash; the only absent
module was the stock ramdisk's out-of-tree `kernelsu` LKM. No partition was
written, and a normal reboot restored the stock kernel. Full evidence is in
[`m3-boot-integration.md`](m3-boot-integration.md).

## Prohibited before later gates

No flashing, repartitioning, AVB-state changes, KernelSU integration,
hardware-forward-port patches, dual-boot selector, overclocking, or thermal
policy bypass is part of M0/M1/M2/M3.

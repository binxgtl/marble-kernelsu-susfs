# M4 KernelSU Next integration

M4 builds the M3-proven kernel again with KernelSU Next compiled directly into
the source tree. Everything the device already booted stays exactly as it was:
the same ACK commit, the same pinned clang, the same ThinLTO, CFI and
shadow-call-stack settings, and the same generic ramdisk at packaging time. The
only intended difference in the produced kernel is KernelSU.

SUSFS is **not** part of M4. It is a separate later milestone, and the
integration script fails outright if the pinned KernelSU tree references it.

## Pinned input

| Field | Value |
|---|---|
| Repository | `https://github.com/KernelSU-Next/KernelSU-Next.git` |
| Tag | `v3.3.0` (latest stable, published 2026-07-03) |
| Commit | `3b18216f71df189ab3d1b1ce0bdb21be1268e771` |
| Derived in-tree version | `KSU_VERSION=33214` (30000 + 3214 commits) |

The pin lives in [`manifests/sources.lock`](../manifests/sources.lock) alongside
every other input. The upstream default branch is `dev`; a floating branch is
never used.

The installed userspace on the target already reports `ksud 3.3.0 (uapi: 2)`,
so pinning the kernel side to the same release keeps the two halves aligned.

## Why the upstream setup script is not used

`kernel/setup.sh` upstream clones the default branch and runs `git pull` before
checking anything out, and it cannot assert what version the result will report.
[`scripts/m4-integrate-kernelsu.sh`](../scripts/m4-integrate-kernelsu.sh)
performs the same three edits against the pinned commit instead:

1. symlink `common/drivers/kernelsu` to the KernelSU `kernel/` directory,
2. append `obj-$(CONFIG_KSU) += kernelsu/` to `common/drivers/Makefile`,
3. insert `source "drivers/kernelsu/Kconfig"` into `common/drivers/Kconfig`.

No existing kernel source file is patched. KernelSU Next v3.3.0 hooks through
LSM hooks, a syscall-hook manager and kprobes, so the `fs/*.c` patch sets that
older or non-GKI integrations need do not apply here.

The script is idempotent, supports `--cleanup`, and refuses to run when the
tree does not look the way it expects — for example if `drivers/Kconfig` has
more than one `endmenu`, rather than editing blindly.

### The version determinism trap

KernelSU's `kernel/Kbuild` derives its version from
`git rev-list --count HEAD`, and it takes three paths that are unsuitable for a
reproducible build:

- if the clone is shallow it runs `git fetch --unshallow` **during the kernel
  build**, which means network access mid-build and a version that depends on
  when the build ran;
- if the directory is not a git repository at all it falls back to
  `KSU_VERSION=1` and tag `v0.0.1`;
- if it resolves to the *same* git root as the kernel it skips version
  detection entirely and takes that same fallback, which is why KernelSU is
  cloned as a sibling of `common/` and symlinked in rather than copied inside.

The integration script therefore clones at full depth, asserts the clone is not
shallow, and asserts both the commit count and the tag. CI additionally asserts
that the build log contains the expected version and tag, and fails if the
fallback warning appears.

## Configuration delta

Upstream declares `config KSU` as `tristate`, `default y`, `depends on KPROBES
&& EXT4_FS`. Both dependencies are already `=y` in the M1 baseline, so the
entire delta is one symbol:

```
CONFIG_KSU=y
```

That single line lives in [`configs/kernelsu.fragment`](../configs/kernelsu.fragment),
which is applied *in addition to* `baseline.fragment` through the
`EXTRA_FRAGMENTS` variable. `EXTRA_FRAGMENTS` is empty for M1, so the M1
command line is unchanged and M1 must keep producing
`image_sha256=15b59c1353825516c415fbedfb98593f01cdf997f848e542b0a6bb98b7e52353`.
That value was reproduced byte-for-byte by two independent M1 runs, so it is a
usable regression anchor rather than a hope.

`scripts/verify-config.sh` still runs inside the build and still requires
`CONFIG_LTO_CLANG_THIN`, `CONFIG_CFI_CLANG`, `CONFIG_SHADOW_CALL_STACK`,
`CONFIG_MODVERSIONS` and the rest of the baseline invariants, so an M4 build
cannot quietly drift away from what booted.

## Keeping the KMI gate honest

The pinned KernelSU tree contains **no `EXPORT_SYMBOL` at all** and no headers
outside its own directory, so it should not move the exported symbol surface.
That expectation is enforced rather than assumed, in three layers:

1. the integration script refuses a KernelSU tree that contains
   `EXPORT_SYMBOL`;
2. [`scripts/m4-kmi-digest.py`](../scripts/m4-kmi-digest.py) recomputes an
   order-independent digest of `Module.symvers` and compares it against the
   frozen baseline in [`manifests/kmi-baseline.txt`](../manifests/kmi-baseline.txt).
   The digest covers the sorted set of `symbol / CRC / export type` records, so
   link-order churn cannot cause a false alarm while a real CRC or symbol change
   cannot slip through;
3. the provider-aware M2 comparison (`scripts/m2-verify-kmi.py`) runs again
   against the M4 `Module.symvers`, so every stock vendor-module requirement is
   rechecked against the kernel that will actually be packaged.

## Producing the test image

M4 introduces no new packaging. Once the artifact is downloaded, the existing
M3 pipeline is used unchanged:

```bash
./scripts/m3-build-test-image.sh /path/to/stock-boot.img /path/to/Image
```

## Gate

Status is **BUILD PENDING** until the M4 workflow is green. No device operation
is part of M4, and the same prohibitions as
[`recovery.md`](recovery.md) apply: the first and only permitted hardware step
remains a non-writing `fastboot boot`, and it happens after the artifact and its
hashes have been reported and reviewed.

## Open risks

- **5.10 compilation is unproven here.** The KernelSU sources carry
  `LINUX_VERSION_CODE` branches below 5.11, so 5.10 is a handled case upstream,
  but this project has not compiled it yet. The build is the test.
- **CFI plus ThinLTO against syscall-table patching.** KernelSU includes
  `hook/arm64/patch_memory.o`, and the baseline enables `CONFIG_CFI_CLANG` with
  ThinLTO. This is the most likely place for the build or the boot to break, and
  neither reading the source nor further research can settle it. Only a build
  and then the hardware gate can.

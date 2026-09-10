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

Status is **HARDWARE PASS** as of 2026-09-10. As at M3, the gate was a single
ephemeral `fastboot boot`; no partition was written and the prohibitions in
[`recovery.md`](recovery.md) applied throughout.

### Build result

| Item | Value |
|---|---|
| `Image` | `17ca7970f2cccccc537fc6ea2bfb1cbd5a5e05d2512e7f8315343b66f89febc1`, 38604684 bytes |
| Baseline `Image` it must differ from | `15b59c1353825516c415fbedfb98593f01cdf997f848e542b0a6bb98b7e52353` |
| `kernel_release` | `5.10.236-gb97c62c4e7d1-dirty` |
| `lto_mode` | `thin`, unchanged |
| In-tree KernelSU version | `33214`, tag `v3.3.0`, with no fallback warning |
| `Module.symvers` | `a53147dba0f7475607f08978e8cc2099a39a43c3d0c99a2063b052f561b35ff5` — **byte-identical to the M1 baseline** |
| Config delta vs M1 | exactly 9 lines, all of them KernelSU |
| Provider-aware gate | 18368 of 18368 symbol requirements matched, 0 missing, 0 mismatches |

### Hardware result

| Item | Value |
|---|---|
| Test image | `3fcc3ac97f033218d31ad1df457a3afa4a0c8749a628f7d5054d74c508d9e988`, 39989248 bytes |
| `uname -r` | `5.10.236-gb97c62c4e7d1-dirty` |
| `sys.boot_completed` | **1, at 28 s uptime** |
| `/proc/modules` | 418, the identical set to the M3 pass |
| Module load errors | none in dmesg: zero unknown-symbol, version-magic or CRC messages |
| Root | `su -c id` returns `uid=0(root) ... context=u:r:ksu:s0` |
| Kernel version seen by userspace | `ksud debug version` reports `Kernel Version: 33214` |
| CFI violations | **zero** |
| Panics / oopses | **zero** |
| Rollback | a normal reboot returned to the stock kernel with all 419 modules |

`kernelsu` no longer appears in `/proc/modules`, which is the point of this
milestone: it is compiled into the kernel rather than force-loaded as an
out-of-tree module by a patched ramdisk. The stock boot partition force-loads it
with `no symbol version for module_layout` and taints the kernel; the M4 kernel
does neither.

The two dmesg warnings observed — `enable_irq` at `kernel/irq/manage.c:691`
from `spi_geni_runtime_resume`, and the unprivileged-eBPF Spectre notice — are
present identically on the stock kernel, so neither is an M4 regression. That
was checked against a stock dmesg captured beforehand rather than assumed.

### On the `-dirty` suffix

Integrating KernelSU modifies `drivers/Makefile` and `drivers/Kconfig` and adds
an untracked symlink, so `setlocalversion` marks the release string dirty. This
is accurate rather than a defect: the tree genuinely is modified. It does not
affect module loading, because with `MODVERSIONS` the kernel's `same_magic()`
compares only the flag suffix after the first space, and that suffix is
unchanged. M3 already demonstrated this in practice, where stock modules built
against `5.10.160-gki-...` loaded onto a `5.10.236-gb97c62c4e7d1` kernel.

## Risks that were open before the build, and how they resolved

- **5.10 compilation.** Resolved: the build is green. All seven hook objects
  compile, including `hook/arm64/patch_memory.o` and `hook/arm64/syscall_hook.o`.
- **CFI plus ThinLTO against syscall-table patching.** Resolved: no build error,
  and zero CFI violations at runtime across a full boot to
  `sys.boot_completed`. KernelSU patched syscall slot 42 and installed its
  dispatcher cleanly.

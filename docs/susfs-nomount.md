# Independent SUSFS / NoMount engineering record

## Scope and provenance

Operator request, 2026-10-04: use a separate repository/folder, begin from the
completed source-integrated KernelSU Next M4 project, prioritize SUSFS and
NoMount, use GitHub-hosted workers and Full LTO. All work is software-only until
the operator is notified for a reviewed hardware test.

Project base: `d9d2c1e03ee81fa61feb79138c402fb8cc04bc00` in
`https://github.com/binxgtl/marble-native-linux`.
Original project's live branch and HEAD were read-only:
`m9/kgsl-turnip-scanout`, `766f3582d7867d17e93e196d435b257ffe1cd411`.
Its worktree was clean before this independent project was created.
No hardware, milestone or binary freeze is changed by this fork.

Reference release: [WildKernels r21](https://github.com/WildKernels/GKI_KernelSU_SUSFS/releases/tag/r21),
builder commit `e0ecd61219baaa0c3eae821246e31136302fd0dc`.
The operator explicitly selected [SUSFS 9892175](https://gitlab.com/simonpunk/susfs4ksu/-/commit/9892175b4acec7ee844e113b8d02c0f4d12cdfac).
Every source pin and the exact four SUSFS input-file hashes are in
`manifests/features.lock.json`. No floating setup script is executed.

## Root integration decision

Historical M4 pins official KernelSU Next v3.3.0,
`3b18216f71df189ab3d1b1ce0bdb21be1268e771`, in-tree version 33214.
That kernel tree has no KSU_SUSFS configuration or the SUSFS 2.3 core-hook API.
The SUSFS `10_enable_susfs_for_ksu.patch` targets original KernelSU and changes
its hook implementation; it is not an applicable generic patch for that M4
Next source tree.

This project therefore uses r21's [SUSFS-enabled Next source](https://github.com/pershoot/KernelSU-Next/tree/4c5853188012f63a1a1fedd4a57fda6375fecb38).
The pinned fork is 107 commits ahead of the M4 shared base. Its kernel-only
diff contains 56 files, 3430 additions and 595 deletions. That broader root
upgrade is explicit and remains unproven on this device.
The selected full-depth commit has 3321 reachable commits and nearest tag
v3.4.0. The project fixes version 33321 and v3.4.0 in Kbuild from those verified
inputs: upstream's remote-branch merge-base calculation must not determine a
build's version differently as the branch moves.
An existing Manager APK is not evidence of compatibility or working root with
the resulting kernel; matching userspace must be assessed before hardware.

## Exact ACK patch port

Unmodified upstream patch SHA256:
`66ea9b816670cf7ead7d9706a319a3143dcaa7ca15cdb9cf5ed2e6d8539b2a26`.
It touches 24 ACK files, including VFS, proc, MM, input, reboot and SELinux code.
The upstream `show_smap` hunk expects `struct vm_area_struct *vma = v;`.
Our exact ACK uses `pad_vma = get_pad_vma(v)` and `vma = get_data_vma(v)`.
The integrator changes only those context lines and hunk counts, preserving
the SUSFS conditional, ACK's padding declarations, memset and show_pad path.

Ported patch SHA256:
`6d9e43593d53c096e2a47a68483d78ca475b29a961f36d6bc75fdb5e87f42e33`.
Local exact-source `git apply --check` passed all hunks. It used a read-only
check, not a local compile. Changed inputs or changed hunk context cause a hard
failure rather than fuzz, ignored rejects or a skipped feature.

KSU and NoMount are sibling source repositories and linked into drivers/fs.
SUSFS source files are copied from the checked exact commit. New exports in
KSU/NoMount are rejected; generated Module.symvers still has to pass the original
canonical KMI digest and the stock provider/CRC gate. No KMI pass is inferred
from the source scan or the patch check.

## NoMount and userspace

[Pinned NoMount source](https://github.com/maxsteeel/nomount/tree/5a610db7649a59eb3e3d710653618d594941f8da)
defines version 20, registers a Linux key type and requires CAP_SYS_ADMIN for
its control interface. CONFIG_KEYS and CONFIG_NOMOUNT are required. It modifies
VFS operation callbacks when userspace installs rules; empty rule tables do
not perform a redirection.

The separate metamodule/control binary supplies rules and redirects module
payload paths. This project packages the built-in interface only; it does not
use an LKM loader or a module-version bypass. SUSFS also needs its matching
userspace control tool/module for configuration. Neither package is installed
or run on the phone by CI or integration scripts.

SUSFS and NoMount both affect VFS paths. Their combined behavior, callback CFI,
root-manager/daemon compatibility and device performance are runtime unknowns.
No runtime hiding, root-detection result or module functionality is claimed.
Default hiding/redirect policies are not installed during engineering.

## Build policy and stop boundary

GitHub-hosted `ubuntu-24.04` is explicitly authorized here despite the original
project's self-hosted policy. Full LTO is selected by the final config fragment;
CFI, shadow call stack, PREEMPT, module support and MODVERSIONS remain required.
Build resources and compiler identity are recorded. The old M4 ThinLTO
Image/boot hashes remain historical evidence, not hashes expected of this new
Full-LTO/root-upgrade kernel.

Build, KMI, staged-boot identity and hardware remain unproven until their gates
actually run. A failed gate stops staging. A new kernel must not replace the
original project's frozen diagnostic carrier.

Dependencies are fetched as public source with their original notices retained:
ACK (GPL-2.0), KernelSU Next, SUSFS and NoMount (upstream GPL-family notices).
Source repositories, exact commits and the project's modifications must
accompany redistributed artifacts; no proprietary ROM content is public.

Subsequent build/boot evidence and the narrowly authorized installation are
recorded in [the 2026-10-04 test record](boot-test-2026-10-04.md). The release
suffix policy for new builds uses .scmversion to retain the upstream commit
suffix without dirty. Source modifications remain explicit in the integration
report and tracked_source_diff_sha256 build metadata; this is not a claim of an
unmodified upstream kernel.

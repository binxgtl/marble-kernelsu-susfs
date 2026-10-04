#!/usr/bin/env bash
set -euo pipefail

root=$(realpath -m "${1:-work}")
artifacts=$(realpath -m "${2:-artifacts}")
source_dir="$root/common"
toolchain_dir="$root/clang-r416183b"
out_dir="$root/out"

test -d "$source_dir/.git"
test -x "$toolchain_dir/bin/clang"
scripts/pin-kernel-scm.sh "$source_dir"

jobs=${BUILD_JOBS:-2}
export PATH="$toolchain_dir/bin:$PATH"
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_COMPAT=arm-linux-gnueabi-
export KCFLAGS="${KCFLAGS:-} -D__ANDROID_COMMON_KERNEL__"
export KBUILD_BUILD_USER=marble-ci
export KBUILD_BUILD_HOST=github-actions
export KBUILD_BUILD_TIMESTAMP="1970-01-01 00:00:00 UTC"

make_args=(
  -C "$source_dir"
  O="$(realpath -m "$out_dir")"
  ARCH="$ARCH"
  LLVM="$LLVM"
  LLVM_IAS="$LLVM_IAS"
)

make "${make_args[@]}" gki_defconfig
# EXTRA_FRAGMENTS is intentionally unquoted so a caller can pass several paths.
# It is empty for M1, which keeps this command byte-identical to the build that
# produced the M3-proven Image.
"$source_dir/scripts/kconfig/merge_config.sh" -m -O "$out_dir" \
  "$out_dir/.config" configs/baseline.fragment ${EXTRA_FRAGMENTS:-}
make "${make_args[@]}" olddefconfig

scripts/verify-features-config.sh "$out_dir/.config"
make "${make_args[@]}" -j"$jobs" Image Image.lz4 modules 2>&1 | tee "$root/build.log"

mkdir -p "$artifacts"
cp "$out_dir/arch/arm64/boot/Image" "$artifacts/Image"
cp "$out_dir/arch/arm64/boot/Image.lz4" "$artifacts/Image.lz4"
cp "$out_dir/.config" "$artifacts/config"
cp "$out_dir/System.map" "$artifacts/System.map"
cp "$out_dir/Module.symvers" "$artifacts/Module.symvers"
cp "$root/build.log" "$artifacts/build.log"
cp "$root/toolchain-version.txt" "$artifacts/toolchain-version.txt"

module_source_list=$(mktemp)
module_copy_list=$(mktemp)
trap 'rm -f "$module_source_list" "$module_copy_list"' EXIT
find "$out_dir" -type f -name '*.ko' -printf '%P\n' | LC_ALL=C sort >"$module_source_list"
module_count=$(wc -l <"$module_source_list")
module_config_count=$(grep -c '=m$' "$out_dir/.config" || true)
if (( module_config_count > 0 && module_count == 0 )); then
  echo ".config enables $module_config_count modular options but the build produced no .ko files" >&2
  exit 1
fi

mkdir -p "$artifacts/modules"
rsync -a --delete --include='*/' --include='*.ko' --exclude='*' \
  "$out_dir/" "$artifacts/modules/"
find "$artifacts/modules" -type f -name '*.ko' -printf '%P\n' |
  LC_ALL=C sort >"$module_copy_list"
if ! cmp -s "$module_source_list" "$module_copy_list"; then
  echo "module artifact copy does not match the build output" >&2
  diff -u "$module_source_list" "$module_copy_list" >&2 || true
  exit 1
fi
cp "$module_source_list" "$artifacts/modules-list.txt"
(
  cd "$artifacts"
  while IFS= read -r module; do
    sha256sum "modules/$module"
  done <modules-list.txt >modules-SHA256SUMS
)

kernel_release=$(make -s "${make_args[@]}" kernelrelease)
lto_mode=full # verify-features-config.sh requires FULL=y and THIN unset.
config_sha=$(sha256sum "$out_dir/.config" | awk '{print $1}')
image_sha=$(sha256sum "$artifacts/Image" | awk '{print $1}')
image_lz4_sha=$(sha256sum "$artifacts/Image.lz4" | awk '{print $1}')
source_sha=$(git -C "$source_dir" rev-parse HEAD)
source_diff_sha=$(git -C "$source_dir" diff --binary HEAD | sha256sum | awk '{print $1}')

{
  printf 'source_sha=%s\n' "$source_sha"
  printf 'scm_suffix=-g%s\n' "${source_sha:0:12}"
  printf 'scm_policy=pinned upstream commit; integrated source modifications recorded separately\n'
  printf 'tracked_source_diff_sha256=%s\n' "$source_diff_sha"
  printf 'kernel_release=%s\n' "$kernel_release"
  printf 'lto_mode=%s\n' "$lto_mode"
  printf 'config_sha256=%s\n' "$config_sha"
  printf 'image_sha256=%s\n' "$image_sha"
  printf 'image_lz4_sha256=%s\n' "$image_lz4_sha"
  printf 'build_jobs=%s\n' "$jobs"
  printf 'module_count=%s\n' "$module_count"
  printf 'modular_config_count=%s\n' "$module_config_count"
} | tee "$artifacts/build-metadata.txt"

(cd "$artifacts" && sha256sum Image Image.lz4 config System.map Module.symvers modules-list.txt modules-SHA256SUMS > SHA256SUMS)

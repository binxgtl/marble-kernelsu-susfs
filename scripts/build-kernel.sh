#!/usr/bin/env bash
set -euo pipefail

root=$(realpath -m "${1:-work}")
artifacts=$(realpath -m "${2:-artifacts}")
source_dir="$root/common"
toolchain_dir="$root/clang-r416183b"
out_dir="$root/out"

test -d "$source_dir/.git"
test -x "$toolchain_dir/bin/clang"

jobs=${BUILD_JOBS:-2}
export PATH="$toolchain_dir/bin:$PATH"
export ARCH=arm64
export LLVM=1
export LLVM_IAS=1
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
"$source_dir/scripts/kconfig/merge_config.sh" -m -O "$out_dir" \
  "$out_dir/.config" configs/baseline.fragment
make "${make_args[@]}" olddefconfig

scripts/verify-config.sh "$out_dir/.config"
make "${make_args[@]}" -j"$jobs" Image Image.lz4 modules 2>&1 | tee "$root/build.log"

mkdir -p "$artifacts"
cp "$out_dir/arch/arm64/boot/Image" "$artifacts/Image"
cp "$out_dir/arch/arm64/boot/Image.lz4" "$artifacts/Image.lz4"
cp "$out_dir/.config" "$artifacts/config"
cp "$out_dir/System.map" "$artifacts/System.map"
cp "$out_dir/Module.symvers" "$artifacts/Module.symvers"
cp "$root/build.log" "$artifacts/build.log"
cp "$root/toolchain-version.txt" "$artifacts/toolchain-version.txt"

kernel_release=$(make -s "${make_args[@]}" kernelrelease)
config_sha=$(sha256sum "$out_dir/.config" | awk '{print $1}')
image_sha=$(sha256sum "$artifacts/Image" | awk '{print $1}')
image_lz4_sha=$(sha256sum "$artifacts/Image.lz4" | awk '{print $1}')
source_sha=$(git -C "$source_dir" rev-parse HEAD)

{
  printf 'source_sha=%s\n' "$source_sha"
  printf 'kernel_release=%s\n' "$kernel_release"
  printf 'config_sha256=%s\n' "$config_sha"
  printf 'image_sha256=%s\n' "$image_sha"
  printf 'image_lz4_sha256=%s\n' "$image_lz4_sha"
  printf 'build_jobs=%s\n' "$jobs"
} | tee "$artifacts/build-metadata.txt"

(cd "$artifacts" && sha256sum Image Image.lz4 config System.map Module.symvers > SHA256SUMS)

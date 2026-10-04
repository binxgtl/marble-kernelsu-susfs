#!/usr/bin/env bash
set -euo pipefail

project=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root=$(realpath -m "${1:-work}")
artifacts=$(realpath -m "${2:-artifacts/userspace}")
lock_file=${FEATURES_LOCK_FILE:-"$project/manifests/features.lock.json"}

susfs_dir="$root/susfs4ksu"
nomount_dir="$root/NoMount"
ndk_root=${ANDROID_NDK_ROOT:-${ANDROID_NDK_HOME:-}}
if [[ -z "$ndk_root" ]]; then
  echo 'ANDROID_NDK_ROOT must point to the pinned Android NDK 27.2.12479018' >&2
  exit 2
fi
ndk_root=$(realpath -m "$ndk_root")
ndk_build="$ndk_root/ndk-build"
clang="$ndk_root/toolchains/llvm/prebuilt/linux-x86_64/bin/clang"
llvm_readelf="$ndk_root/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-readelf"

for path in "$lock_file" "$susfs_dir/.git" "$nomount_dir/.git" \
            "$ndk_root/source.properties" "$ndk_build" "$clang" "$llvm_readelf"; do
  test -e "$path" || { echo "required input is missing: $path" >&2; exit 2; }
done
test -x "$ndk_build" && test -x "$clang"

read_lock() {
  python3 - "$lock_file" "$1" "$2" <<'PY'
import json
import sys
from pathlib import Path

lock = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(lock["inputs"][sys.argv[2]][sys.argv[3]])
PY
}

expected_susfs=$(read_lock susfs commit)
expected_nomount=$(read_lock nomount commit)
expected_susfs_version=$(read_lock susfs version)
expected_nomount_version=$(read_lock nomount version)
expected_susfs_dir=$(read_lock susfs directory)
expected_nomount_dir=$(read_lock nomount directory)
test "$expected_susfs_dir" = susfs4ksu
test "$expected_nomount_dir" = NoMount

actual_susfs=$(git -C "$susfs_dir" rev-parse HEAD)
actual_nomount=$(git -C "$nomount_dir" rev-parse HEAD)
test "$actual_susfs" = "$expected_susfs" || {
  echo "SUSFS source mismatch: expected $expected_susfs, got $actual_susfs" >&2
  exit 1
}
test "$actual_nomount" = "$expected_nomount" || {
  echo "NoMount source mismatch: expected $expected_nomount, got $actual_nomount" >&2
  exit 1
}
test -z "$(git -C "$susfs_dir" status --porcelain)" || {
  echo 'refusing to build from a modified SUSFS checkout' >&2
  exit 1
}
test -z "$(git -C "$nomount_dir" status --porcelain)" || {
  echo 'refusing to build from a modified NoMount checkout' >&2
  exit 1
}

susfs_header="$susfs_dir/kernel_patches/include/linux/susfs.h"
nomount_header="$nomount_dir/kernel/src/nomount.h"
test -f "$susfs_header" && test -f "$nomount_header"
grep -qxF "#define SUSFS_VERSION \"$expected_susfs_version\"" "$susfs_header"
grep -qxF "#define NOMOUNT_VERSION \"$expected_nomount_version\"" "$nomount_header"
test "$expected_susfs_version" = v2.3.0
test "$expected_nomount_version" = 20

ndk_revision=$(sed -n 's/^Pkg.Revision = //p' "$ndk_root/source.properties" | head -n 1)
test "$ndk_revision" = 27.2.12479018 || {
  echo "expected Android NDK 27.2.12479018, got ${ndk_revision:-unknown}" >&2
  exit 1
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/marble-userspace.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$artifacts"

# Build from a temporary copy. SUSFS upstream selects ThinLTO, so replace its
# two build flags with FullLTO without modifying the pinned checkout.
susfs_build="$tmp/ksu_susfs"
cp -a "$susfs_dir/ksu_susfs" "$susfs_build"
android_mk="$susfs_build/jni/Android.mk"
application_mk="$susfs_build/jni/Application.mk"
test -f "$android_mk" && test -f "$application_mk"
thin_flags=$(grep -oF -- '-flto=thin' "$android_mk" | wc -l | tr -d ' ')
test "$thin_flags" = 2 || {
  echo "expected two upstream ThinLTO flags in SUSFS Android.mk, found $thin_flags" >&2
  exit 1
}
sed -i 's/-flto=thin/-flto=full/g' "$android_mk"
grep -qxF 'APP_PLATFORM := latest' "$application_mk" || {
  echo 'unexpected SUSFS Application.mk platform setting' >&2
  exit 1
}
sed -i 's/^APP_PLATFORM := latest$/APP_PLATFORM := android-30/' "$application_mk"
test "$(grep -oF -- '-flto=full' "$android_mk" | wc -l | tr -d ' ')" = 2
! grep -qF -- '-flto=thin' "$android_mk"

jobs=${BUILD_JOBS:-2}
[[ "$jobs" =~ ^[1-9][0-9]*$ ]]
"$ndk_build" -C "$susfs_build" -j"$jobs" \
  NDK_PROJECT_PATH="$susfs_build" \
  APP_BUILD_SCRIPT="$android_mk" \
  NDK_APPLICATION_MK="$application_mk" \
  APP_ABI=arm64-v8a APP_PLATFORM=android-30
susfs_binary="$susfs_build/libs/arm64-v8a/ksu_susfs"
test -s "$susfs_binary"
"$llvm_readelf" -h "$susfs_binary" | grep -q 'Machine:.*AArch64'

# NoMount's command-line tool is freestanding and uses its own syscall ABI.
nomount_binary="$tmp/nm"
"$clang" --target=aarch64-linux-android30 \
  -Oz -mcmodel=tiny -static -nostdlib -ffreestanding \
  -fno-unwind-tables -fno-ident -Wno-invalid-noreturn -flto=full \
  -fuse-ld=lld -Wl,--entry=_start -Wl,--build-id=none \
  "$nomount_dir/userspace/src/nm.c" -o "$nomount_binary"
test -s "$nomount_binary"
"$llvm_readelf" -h "$nomount_binary" | grep -q 'Machine:.*AArch64'

# Produce the SUSFS control module with the binary built from this pin.
susfs_package="$artifacts/susfs-module"
nomount_package="$artifacts/nomount-module"
rm -rf "$susfs_package" "$nomount_package"
mkdir -p "$susfs_package" "$nomount_package"
cp -a "$susfs_dir/ksu_module_susfs/." "$susfs_package/"
install -m 0644 "$susfs_dir/LICENSE" "$susfs_package/LICENSE"
install -m 0755 "$susfs_binary" "$susfs_package/tools/ksu_susfs_arm64"
susfs_zip="$artifacts/KernelSU-Next-SUSFS-${expected_susfs_version}-arm64.zip"
(
  cd "$susfs_package"
  zip -X -qr "$susfs_zip" .
)

# Stage the pinned NoMount metamodule with only the built-in KernelSU API.
cp -a "$nomount_dir/module/." "$nomount_package/"
rm -rf "$nomount_package/bin" "$nomount_package/lkm"
mkdir -p "$nomount_package/bin"
install -m 0644 "$nomount_dir/LICENSE" "$nomount_package/LICENSE"
install -m 0755 "$nomount_binary" "$nomount_package/bin/nm"

python3 - "$nomount_package/module.prop" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
if text.count("versionCode=\n") != 1:
    raise SystemExit("unexpected NoMount module versionCode field")
path.write_text(text.replace("versionCode=\n", "versionCode=20000\n"), encoding="utf-8", newline="\n")
PY
grep -qx 'versionCode=20000' "$nomount_package/module.prop"

uninstall="$nomount_package/uninstall.sh"
grep -qx 'rm -rf /data/adb/nomount/ /data/adb/ksu/bin/nm /data/adb/ap/bin/nm || true' "$uninstall"
sed -i 's#rm -rf /data/adb/nomount/ /data/adb/ksu/bin/nm /data/adb/ap/bin/nm || true#rm -rf /data/adb/nomount/ /data/adb/ksu/bin/nm || true#' "$uninstall"
! grep -q '/data/adb/ap/' "$uninstall"

grep -qx '    echo "\[FATAL\] Bootloop detected! NoMount caused a crash on the last boot\." >> "$LOG_FILE"' \
  "$nomount_package/metamount.sh"
sed -i 's/Bootloop detected! NoMount caused a crash on the last boot\./Previous boot did not clear the NoMount startup marker./' \
  "$nomount_package/metamount.sh"

cat >"$nomount_package/customize.sh" <<'CUSTOMIZE'
#!/system/bin/sh

fail() {
    if command -v abort >/dev/null 2>&1; then
        abort "$1"
    fi
    echo "$1" >&2
    exit 1
}

if [ "${KSU:-false}" != "true" ]; then
    fail "! This package requires the KernelSU install API."
fi
if command -v ui_print >/dev/null 2>&1; then
    ui_print "- NoMount built-in KernelSU package"
fi
if ! command -v set_perm >/dev/null 2>&1; then
    fail "! KernelSU set_perm API is unavailable."
fi
if [ ! -x "$MODPATH/bin/nm" ]; then
    fail "! The arm64 NoMount userspace tool is missing."
fi

set_perm "$MODPATH/bin/nm" 0 0 0755
api_version=$("$MODPATH/bin/nm" version 2>/dev/null) || fail "! Built-in NoMount API is unavailable."
if [ "$api_version" != "20" ]; then
    fail "! Expected built-in NoMount API v20; received '${api_version:-no response}'."
fi

mkdir -p /data/adb/ksu/bin
ln -sf /data/adb/modules/nomount/bin/nm /data/adb/ksu/bin/nm
if command -v ui_print >/dev/null 2>&1; then
    ui_print "- Built-in NoMount API v20 verified."
fi
CUSTOMIZE
chmod 0755 "$nomount_package/customize.sh"

# Strip the upstream LKM loader and replace its built-in/LKM probe with a
# version check against the built-in API only. This edits the staged package,
# never the pinned checkout, and fails if the pinned script layout drifts.
python3 - "$nomount_package/metamount.sh" "$expected_nomount_version" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
version = sys.argv[2]
text = path.read_text(encoding="utf-8")
function_start = "load_ko() {\n"
function_end = '\nif [ ! -d "$NOMOUNT_DATA" ]; then'
if text.count(function_start) != 1 or text.count(function_end) != 1:
    raise SystemExit("unexpected NoMount metamount loader function layout")
start = text.index(function_start)
end = text.index(function_end, start)
text = text[:start] + text[end + 1:]

check_start = 'echo "[INFO] Checking NoMount kernel support..." >> "$LOG_FILE"\n'
check_end = '\nfor mod_path in "$MODULES_DIR"/*; do'
if text.count(check_start) != 1 or text.count(check_end) != 1:
    raise SystemExit("unexpected NoMount built-in/LKM probe layout")
start = text.index(check_start)
end = text.index(check_end, start)
replacement = "\n".join([
    f'echo "[INFO] Checking built-in NoMount API v{version}..." >> "$LOG_FILE"',
    'api_version=$("$LOADER" version 2>/dev/null) || api_version=""',
    f'if [ "$api_version" != "{version}" ]; then',
    f'    echo "[FATAL] Built-in NoMount API v{version} is missing or mismatched." >> "$LOG_FILE"',
    '    touch "$MODDIR/disable"',
    '    rm -f "$BOOT_SEMAPHORE"',
    '    exit 1',
    'fi',
    'echo "[OK] Built-in NoMount API v$api_version detected." >> "$LOG_FILE"',
    '',
])
text = text[:start] + replacement + text[end + 1:]
if any(token in text for token in ("lkmloader", ".ko", "insmod", "load_ko")):
    raise SystemExit("built-in-only NoMount boot script still contains an LKM path")
path.write_text(text, encoding="utf-8", newline="\n")
PY

if grep -nE 'lkmloader|\.ko|insmod|load_ko' \
  "$nomount_package/customize.sh" "$nomount_package/metamount.sh"; then
  echo 'NoMount package still contains an LKM fallback path' >&2
  exit 1
fi

nomount_zip="$artifacts/NoMount-v${expected_nomount_version}-KernelSU-built-in.zip"
(
  cd "$nomount_package"
  zip -X -qr "$nomount_zip" .
)

ndk_build_sha=$(sha256sum "$ndk_build" | awk '{print $1}')
clang_sha=$(sha256sum "$clang" | awk '{print $1}')
lld_sha=$(sha256sum "$(dirname "$clang")/ld.lld" | awk '{print $1}')
susfs_sha=$(sha256sum "$susfs_binary" | awk '{print $1}')
nomount_sha=$(sha256sum "$nomount_binary" | awk '{print $1}')
{
  printf 'susfs_source_commit=%s\n' "$actual_susfs"
  printf 'susfs_version=%s\n' "$expected_susfs_version"
  printf 'nomount_source_commit=%s\n' "$actual_nomount"
  printf 'nomount_api_version=%s\n' "$expected_nomount_version"
  printf 'nomount_module_version_code=20000\n'
  printf 'android_ndk_revision=%s\n' "$ndk_revision"
  printf 'android_api=30\n'
  printf 'userspace_lto=full\n'
  printf 'ndk_build_sha256=%s\n' "$ndk_build_sha"
  printf 'clang_sha256=%s\n' "$clang_sha"
  printf 'ld_lld_sha256=%s\n' "$lld_sha"
  printf 'ksu_susfs_sha256=%s\n' "$susfs_sha"
  printf 'nomount_nm_sha256=%s\n' "$nomount_sha"
  printf 'susfs_module_sha256=%s\n' "$(sha256sum "$susfs_zip" | awk '{print $1}')"
  printf 'nomount_module_sha256=%s\n' "$(sha256sum "$nomount_zip" | awk '{print $1}')"
  printf 'nomount_module_mode=built-in-api-only; no LKM or lkmloader payload\n'
} | tee "$artifacts/userspace-build-metadata.txt"

(
  cd "$artifacts"
  sha256sum "$(basename "$susfs_zip")" "$(basename "$nomount_zip")" userspace-build-metadata.txt \
    >SHA256SUMS
)
echo 'Userspace tools and built-in-only modules created.'

#!/usr/bin/env bash
set -euo pipefail

# Software-only regression suite for the M4 tooling. It never reaches the
# network: the KernelSU Next clone is replaced by a synthetic local repository,
# and the ACK tree is replaced by a minimal fake with just the two files the
# integration edits touch.

root=$(cd "$(dirname "$0")/../.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

. "$root/scripts/m3-python.sh"
m3_resolve_python

git_q() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }

# ---------------------------------------------------------------- KMI digest
sym() { printf '0x%08x\t%s\tvmlinux\tEXPORT_SYMBOL\t\n' "$2" "$1"; }
{ sym alpha 1; sym bravo 2; sym charlie 3; } >"$tmp/base.symvers"
{ sym charlie 3; sym alpha 1; sym bravo 2; } >"$tmp/shuffled.symvers"
{ sym alpha 1; sym bravo 9; sym charlie 3; } >"$tmp/crc-changed.symvers"
{ sym alpha 1; sym bravo 2; } >"$tmp/removed.symvers"
{ sym alpha 1; sym bravo 2; sym charlie 3; sym delta 4; } >"$tmp/added.symvers"
{ sym alpha 1; sym alpha 2; } >"$tmp/duplicate.symvers"
printf 'not-a-symvers-line\n' >"$tmp/malformed.symvers"

digest_of() {
  "$PYTHON" "$root/scripts/m4-kmi-digest.py" "$1" | awk -F= '$1 == "canonical_sha256" {print $2}'
}
base_digest=$(digest_of "$tmp/base.symvers")
test -n "$base_digest"

# The digest must ignore line order but notice any real change.
test "$(digest_of "$tmp/shuffled.symvers")" = "$base_digest"
test "$(digest_of "$tmp/crc-changed.symvers")" != "$base_digest"
test "$(digest_of "$tmp/removed.symvers")" != "$base_digest"
test "$(digest_of "$tmp/added.symvers")" != "$base_digest"

expect_digest_failure() {
  local file=$1 label=$2
  if "$PYTHON" "$root/scripts/m4-kmi-digest.py" "$file" >/dev/null 2>&1; then
    echo "expected $label to be rejected" >&2
    exit 1
  fi
}
expect_digest_failure "$tmp/duplicate.symvers" duplicate-symbol
expect_digest_failure "$tmp/malformed.symvers" malformed-line
expect_digest_failure "$tmp/missing.symvers" missing-file

cat >"$tmp/manifest.txt" <<EOF
# synthetic
baseline|symbols|3
baseline|canonical_sha256|$base_digest
EOF
"$PYTHON" "$root/scripts/m4-kmi-digest.py" "$tmp/base.symvers" --expect-manifest "$tmp/manifest.txt" >/dev/null
for bad in crc-changed removed added; do
  if "$PYTHON" "$root/scripts/m4-kmi-digest.py" "$tmp/$bad.symvers" \
    --expect-manifest "$tmp/manifest.txt" >/dev/null 2>&1; then
    echo "expected $bad to fail the frozen-baseline gate" >&2
    exit 1
  fi
done

# The committed manifest must describe the committed baseline consistently.
grep -q '^baseline|canonical_sha256|[0-9a-f]\{64\}$' "$root/manifests/kmi-baseline.txt"
grep -q '^baseline|image_sha256|[0-9a-f]\{64\}$' "$root/manifests/kmi-baseline.txt"

# --------------------------------------------------------------- integration
make_ksu_repo() {
  local dir=$1 body=${2:-}
  mkdir -p "$dir/kernel"
  printf 'menu "KernelSU"\nconfig KSU\n\ttristate\nendmenu\n' >"$dir/kernel/Kconfig"
  printf 'kernelsu-objs := core/init.o\n%s\n' "$body" >"$dir/kernel/Kbuild"
  git_q init -q "$dir"
  git_q -C "$dir" add -A
  git_q -C "$dir" commit -q -m "synthetic kernelsu"
  git_q -C "$dir" tag v0.0.1-test
  git_q -C "$dir" rev-parse HEAD
}

make_ack() {
  local dir=$1 endmenus=${2:-1}
  mkdir -p "$dir/common/drivers"
  git_q init -q "$dir/common"
  printf 'obj-y += base/\n' >"$dir/common/drivers/Makefile"
  {
    printf 'menu "Device Drivers"\nsource "drivers/base/Kconfig"\n'
    [[ "$endmenus" == "2" ]] && printf 'endmenu\nmenu "Extra"\n'
    printf 'endmenu\n'
  } >"$dir/common/drivers/Kconfig"
  git_q -C "$dir/common" add -A
  git_q -C "$dir/common" commit -q -m "synthetic ack"
}

write_lock() {
  printf '# name|role|url|ref|commit|notes\n' >"$1"
  printf 'kernelsu-next|m4-root|%s|v0.0.1-test|%s|synthetic\n' "$2" "$3" >>"$1"
}

integrate() {
  ( cd "$root" && KSU_EXPECTED_TAG=v0.0.1-test KSU_EXPECTED_COUNT=1 \
      LOCK_FILE="$1" bash scripts/m4-integrate-kernelsu.sh "$2" "${3:-integrate}" )
}

work="$tmp/w1"; mkdir -p "$work"
ksu_sha=$(make_ksu_repo "$tmp/ksu-src")
make_ack "$work"
write_lock "$tmp/lock1" "$tmp/ksu-src" "$ksu_sha"

integrate "$tmp/lock1" "$work" >/dev/null
test -L "$work/common/drivers/kernelsu"
test -e "$work/common/drivers/kernelsu/Kconfig"
grep -q 'obj-$(CONFIG_KSU) += kernelsu/' "$work/common/drivers/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "$work/common/drivers/Kconfig"
# The source line must land inside the menu, not after its end.
grep -B1 '^endmenu' "$work/common/drivers/Kconfig" | grep -q 'drivers/kernelsu/Kconfig'
test ! -f "$work/KernelSU-Next/.git/shallow"

# Running twice must not duplicate either edit.
integrate "$tmp/lock1" "$work" >/dev/null
test "$(grep -c 'CONFIG_KSU' "$work/common/drivers/Makefile")" = "1"
test "$(grep -c 'drivers/kernelsu/Kconfig' "$work/common/drivers/Kconfig")" = "1"

# Cleanup must restore the tree.
integrate "$tmp/lock1" "$work" --cleanup >/dev/null
test ! -e "$work/common/drivers/kernelsu"
if grep -q 'CONFIG_KSU' "$work/common/drivers/Makefile"; then
  echo "cleanup left the Makefile edit behind" >&2
  exit 1
fi
if grep -q 'kernelsu' "$work/common/drivers/Kconfig"; then
  echo "cleanup left the Kconfig edit behind" >&2
  exit 1
fi

# ------------------------------------------------------------- fail-closed
expect_integrate_failure() {
  local lock=$1 workdir=$2 label=$3
  if integrate "$lock" "$workdir" >/dev/null 2>&1; then
    echo "expected $label to fail" >&2
    exit 1
  fi
}

# A drifted version input must stop the build rather than change KSU_VERSION.
w2="$tmp/w2"; mkdir -p "$w2"; make_ack "$w2"
if ( cd "$root" && KSU_EXPECTED_TAG=v0.0.1-test KSU_EXPECTED_COUNT=999 \
     LOCK_FILE="$tmp/lock1" bash scripts/m4-integrate-kernelsu.sh "$w2" ) >/dev/null 2>&1; then
  echo "expected a drifted commit count to fail" >&2
  exit 1
fi

# A KernelSU tree that exports symbols would move the frozen KMI surface.
w3="$tmp/w3"; mkdir -p "$w3"; make_ack "$w3"
exp_sha=$(make_ksu_repo "$tmp/ksu-export" 'EXPORT_SYMBOL(ksu_thing);')
write_lock "$tmp/lock3" "$tmp/ksu-export" "$exp_sha"
expect_integrate_failure "$tmp/lock3" "$w3" exporting-kernelsu

# SUSFS is out of scope for M4 and must be rejected outright.
w4="$tmp/w4"; mkdir -p "$w4"; make_ack "$w4"
sus_sha=$(make_ksu_repo "$tmp/ksu-susfs" '# susfs support')
write_lock "$tmp/lock4" "$tmp/ksu-susfs" "$sus_sha"
expect_integrate_failure "$tmp/lock4" "$w4" susfs-carrying-kernelsu

# An unexpected drivers/Kconfig shape must fail instead of being edited blindly.
w5="$tmp/w5"; mkdir -p "$w5"; make_ack "$w5" 2
expect_integrate_failure "$tmp/lock1" "$w5" two-endmenu-kconfig

# A malformed pin must be rejected before anything is cloned.
write_lock "$tmp/lock6" "$tmp/ksu-src" "not-a-sha"
w6="$tmp/w6"; mkdir -p "$w6"; make_ack "$w6"
expect_integrate_failure "$tmp/lock6" "$w6" malformed-commit-pin

# ------------------------------------------------- committed pin consistency
grep -qE '^kernelsu-next\|m4-root\|https://github\.com/KernelSU-Next/KernelSU-Next\.git\|v3\.3\.0\|[0-9a-f]{40}\|' \
  "$root/manifests/sources.lock"
grep -qx 'CONFIG_KSU=y' "$root/configs/kernelsu.fragment"
# The M4 delta must not restate or contradict any baseline invariant.
if grep -qE '^CONFIG_(LTO|CFI|SHADOW_CALL_STACK|MODVERSIONS|PREEMPT|HZ)' "$root/configs/kernelsu.fragment"; then
  echo "kernelsu.fragment must not touch baseline invariants" >&2
  exit 1
fi

echo "M4 tooling checks passed"

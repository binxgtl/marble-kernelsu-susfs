#!/usr/bin/env bash
set -euo pipefail

# Source-integrate KernelSU Next into the pinned ACK tree.
#
# This deliberately does not use the upstream kernel/setup.sh. That script
# clones the default branch and runs `git pull` before checking anything out,
# which is a floating input, and it cannot assert the resulting in-tree version.
# The three edits it performs are reproduced here against a pinned commit.
#
# The clone must be at FULL depth. KernelSU's Kbuild derives its version from
# `git rev-list --count HEAD`, and when it finds a shallow clone it runs
# `git fetch --unshallow` during the kernel build itself. That would mean
# network access mid-build and a version that depends on when the build ran.

root=${1:-work}
action=${2:-integrate}
lock_file=${LOCK_FILE:-manifests/sources.lock}

source_dir="$root/common"
ksu_dir="$root/KernelSU-Next"
driver_dir="$source_dir/drivers"

# Derived from the pinned commit; asserted so a shallow clone, a rewritten
# history, or an accidentally moved pin cannot silently change KSU_VERSION.
# The overrides exist so the regression suite can drive this script against a
# synthetic repository offline. CI never sets them.
expected_tag=${KSU_EXPECTED_TAG:-v3.3.0}
expected_count=${KSU_EXPECTED_COUNT:-3214}
expected_version=$((30000 + expected_count))

field() {
  local name=$1 column=$2
  awk -F '|' -v name="$name" -v column="$column" '$1 == name { print $column; exit }' "$lock_file"
}

cleanup() {
  local link="$driver_dir/kernelsu"
  [[ -L "$link" ]] && rm "$link" && echo "[-] removed drivers/kernelsu symlink"
  if [[ -f "$driver_dir/Makefile" ]] && grep -q 'CONFIG_KSU' "$driver_dir/Makefile"; then
    sed -i '/kernelsu/d' "$driver_dir/Makefile"
    echo "[-] reverted drivers/Makefile"
  fi
  if [[ -f "$driver_dir/Kconfig" ]] && grep -q 'drivers/kernelsu/Kconfig' "$driver_dir/Kconfig"; then
    sed -i '\#drivers/kernelsu/Kconfig#d' "$driver_dir/Kconfig"
    echo "[-] reverted drivers/Kconfig"
  fi
  echo '[+] cleanup done'
}

if [[ "$action" == "--cleanup" ]]; then
  test -d "$driver_dir" || { echo "no driver directory at $driver_dir" >&2; exit 2; }
  cleanup
  exit 0
fi

url=$(field kernelsu-next 3)
ref=$(field kernelsu-next 4)
commit=$(field kernelsu-next 5)

if [[ -z "$url" || ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
  echo "invalid kernelsu-next entry in $lock_file" >&2
  exit 2
fi
test -d "$source_dir/.git" || { echo "ACK source missing at $source_dir" >&2; exit 2; }
test -d "$driver_dir" || { echo "no drivers/ directory at $driver_dir" >&2; exit 2; }

# --- fetch, pinned and at full depth -----------------------------------------
if [[ ! -d "$ksu_dir/.git" ]]; then
  git clone "$url" "$ksu_dir"
fi
git -C "$ksu_dir" fetch --tags origin
if [[ -f "$ksu_dir/.git/shallow" ]]; then
  git -C "$ksu_dir" fetch --unshallow
fi
git -C "$ksu_dir" checkout --detach "$commit"

test "$(git -C "$ksu_dir" rev-parse HEAD)" = "$commit"
test ! -f "$ksu_dir/.git/shallow"

actual_count=$(git -C "$ksu_dir" rev-list --count HEAD)
actual_tag=$(git -C "$ksu_dir" describe --tags --abbrev=0)
if [[ "$actual_count" != "$expected_count" || "$actual_tag" != "$expected_tag" ]]; then
  echo "FAIL: in-tree version inputs drifted." >&2
  echo "  expected count=$expected_count tag=$expected_tag" >&2
  echo "  actual   count=$actual_count tag=$actual_tag" >&2
  exit 1
fi

# --- guard the properties this milestone depends on --------------------------
# KernelSU Next must export nothing, or the frozen KMI surface would move.
if grep -rq 'EXPORT_SYMBOL' "$ksu_dir/kernel/"; then
  echo "FAIL: the pinned KernelSU Next exports symbols; the KMI gate assumes it does not" >&2
  exit 1
fi
# SUSFS is explicitly out of scope for M4.
if grep -rqi 'susfs' "$ksu_dir/kernel/"; then
  echo "FAIL: the pinned KernelSU Next kernel tree references SUSFS, which M4 excludes" >&2
  exit 1
fi

# --- the three integration edits, idempotent ---------------------------------
relative=$(realpath --relative-to="$driver_dir" "$ksu_dir/kernel")
ln -sfn "$relative" "$driver_dir/kernelsu"

if ! grep -q 'CONFIG_KSU' "$driver_dir/Makefile"; then
  printf '\nobj-$(CONFIG_KSU) += kernelsu/\n' >>"$driver_dir/Makefile"
fi

if ! grep -q 'drivers/kernelsu/Kconfig' "$driver_dir/Kconfig"; then
  # Upstream inserts before every `endmenu`. drivers/Kconfig is expected to have
  # exactly one, and anything else means the tree is not what we think it is.
  endmenus=$(grep -c '^endmenu' "$driver_dir/Kconfig")
  if [[ "$endmenus" != "1" ]]; then
    echo "FAIL: expected exactly one endmenu in drivers/Kconfig, found $endmenus" >&2
    exit 1
  fi
  sed -i 's#^endmenu#source "drivers/kernelsu/Kconfig"\nendmenu#' "$driver_dir/Kconfig"
fi

test -e "$driver_dir/kernelsu/Kconfig"
grep -q 'obj-$(CONFIG_KSU) += kernelsu/' "$driver_dir/Makefile"
grep -q 'source "drivers/kernelsu/Kconfig"' "$driver_dir/Kconfig"

printf 'KernelSU-Next %s (%s) integrated; expected in-tree KSU_VERSION=%s\n' \
  "$commit" "$ref" "$expected_version"

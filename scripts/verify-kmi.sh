#!/usr/bin/env bash
set -euo pipefail

config=${1:?usage: verify-kmi.sh CONFIG METADATA_TSV [MODULE_SYMVERS] [MODULE_DIR]}
metadata=${2:?usage: verify-kmi.sh CONFIG METADATA_TSV [MODULE_SYMVERS] [MODULE_DIR]}
symvers=${3:-}
module_dir=${4:-}

for required in CONFIG_MODULES=y CONFIG_MODULE_UNLOAD=y CONFIG_MODVERSIONS=y CONFIG_PREEMPT=y; do
  grep -qxF "$required" "$config" || {
    echo "FAIL: $required missing" >&2
    exit 1
  }
done

expected_count=$(awk -F '|' '$1 == "vendor_boot_audit" {print $2}' "$metadata")
expected_vermagic=$(awk -F '|' '$1 == "vendor_boot_audit" {print $3}' "$metadata")
test "$expected_count" = "356"
test "$expected_vermagic" = "5.10.160-gki-gd28eeb36ae86 SMP preempt mod_unload modversions aarch64"

{
  echo "KMI compatibility status: STATIC CHECK ONLY — NOT PROVEN"
  echo "Audited vendor modules: $expected_count"
  echo "Audited common vermagic: $expected_vermagic"
  echo "Baseline config: MODULES, MODULE_UNLOAD, MODVERSIONS and PREEMPT enabled"
  if [[ -n "$symvers" && -s "$symvers" ]]; then
    echo "Built Module.symvers: present"
  else
    echo "Built Module.symvers: absent"
  fi
  echo "Reason: proprietary vendor modules are intentionally absent from CI."
} | tee kmi-report.txt

if [[ -z "$module_dir" ]]; then
  exit 0
fi

command -v modinfo >/dev/null || {
  echo "FAIL: modinfo is required for local module verification" >&2
  exit 2
}
test -d "$module_dir"

count=0
bad=0
while IFS= read -r -d '' module; do
  count=$((count + 1))
  actual=$(modinfo -F vermagic "$module" || true)
  if [[ "$actual" != "$expected_vermagic" ]]; then
    echo "vermagic mismatch: $module" >&2
    bad=1
  fi
done < <(find "$module_dir" -type f -name '*.ko' -print0)

test "$count" -gt 0 || {
  echo "FAIL: no .ko modules found in $module_dir" >&2
  exit 2
}

echo "Local metadata scan: $count modules"
if [[ "$bad" -ne 0 ]]; then
  exit 1
fi

echo "Local vermagic scan passed. Symbol CRC compatibility still requires a full module-version comparison and device load test."

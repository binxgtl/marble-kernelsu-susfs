#!/usr/bin/env bash
set -euo pipefail

config=${1:?usage: verify-features-config.sh PATH_TO_CONFIG}
test -f "$config"

required=(
  CONFIG_PREEMPT=y
  CONFIG_HZ=250
  CONFIG_IKCONFIG=y
  CONFIG_IKCONFIG_PROC=y
  CONFIG_UCLAMP_TASK=y
  CONFIG_CGROUPS=y
  CONFIG_MEMCG=y
  CONFIG_BPF=y
  CONFIG_BPF_JIT=y
  CONFIG_KALLSYMS=y
  CONFIG_ENERGY_MODEL=y
  CONFIG_CPU_FREQ=y
  CONFIG_CPU_FREQ_STAT=y
  CONFIG_MODULES=y
  CONFIG_MODULE_UNLOAD=y
  CONFIG_MODVERSIONS=y
  CONFIG_KEYS=y
  CONFIG_LTO=y
  CONFIG_LTO_CLANG=y
  CONFIG_LTO_CLANG_FULL=y
  CONFIG_CFI_CLANG=y
  CONFIG_SHADOW_CALL_STACK=y
  CONFIG_KSU=y
  CONFIG_KSU_SUSFS=y
  CONFIG_KSU_SUSFS_SUS_PATH=y
  CONFIG_KSU_SUSFS_SUS_MOUNT=y
  CONFIG_KSU_SUSFS_SUS_KSTAT=y
  CONFIG_KSU_SUSFS_SPOOF_UNAME=y
  CONFIG_KSU_SUSFS_ENABLE_LOG=y
  CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
  CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
  CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
  CONFIG_KSU_SUSFS_SUS_MAP=y
  CONFIG_NOMOUNT=y
)

failed=0
for setting in "${required[@]}"; do
  if ! grep -qxF "$setting" "$config"; then
    echo "missing required feature config: $setting" >&2
    failed=1
  fi
done

if ! grep -qxF '# CONFIG_LTO_CLANG_THIN is not set' "$config"; then
  echo 'ThinLTO must be unset for this FullLTO build' >&2
  failed=1
fi

exit "$failed"

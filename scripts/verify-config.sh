#!/usr/bin/env bash
set -euo pipefail

config=${1:?usage: verify-config.sh PATH_TO_CONFIG}

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
  CONFIG_SHADOW_CALL_STACK=y
  CONFIG_LTO=y
  CONFIG_LTO_CLANG=y
  CONFIG_CFI_CLANG=y
  CONFIG_MODULES=y
  CONFIG_MODULE_UNLOAD=y
  CONFIG_MODVERSIONS=y
)

failed=0
for setting in "${required[@]}"; do
  if ! grep -qxF "$setting" "$config"; then
    echo "missing required config: $setting" >&2
    failed=1
  fi
done
exit "$failed"

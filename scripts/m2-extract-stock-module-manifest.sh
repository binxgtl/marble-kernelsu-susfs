#!/usr/bin/env bash
set -euo pipefail

module_dir=${1:?usage: m2-extract-stock-module-manifest.sh MODULE_DIRECTORY [OUTPUT_JSON]}
output=${2:-manifests/stock-module-versions.json}
providers_output=${3:-manifests/stock-module-providers.json}

exec python3 scripts/m2-module-manifest.py \
  --expected-modules 356 \
  --validation-count 5 \
  --providers-output "$providers_output" \
  "$module_dir" "$output"

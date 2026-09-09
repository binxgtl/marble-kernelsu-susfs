#!/usr/bin/env bash
set -euo pipefail

dir=${1:-artifacts}
for file in Image Image.lz4 config System.map Module.symvers SHA256SUMS build-metadata.txt; do
  test -s "$dir/$file" || { echo "missing artifact file: $file" >&2; exit 1; }
done
(cd "$dir" && sha256sum -c SHA256SUMS)
scripts/verify-config.sh "$dir/config"
file "$dir/Image" "$dir/Image.lz4"
sed -n '1,120p' "$dir/build-metadata.txt"

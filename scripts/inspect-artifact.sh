#!/usr/bin/env bash
set -euo pipefail

dir=${1:-artifacts}
for file in Image Image.lz4 config System.map Module.symvers SHA256SUMS build-metadata.txt; do
  test -s "$dir/$file" || { echo "missing artifact file: $file" >&2; exit 1; }
done
for file in modules-list.txt modules-SHA256SUMS; do
  test -e "$dir/$file" || { echo "missing artifact file: $file" >&2; exit 1; }
done
(cd "$dir" && sha256sum -c SHA256SUMS)
scripts/verify-config.sh "$dir/config"

actual_modules=$(mktemp)
trap 'rm -f "$actual_modules"' EXIT
LC_ALL=C sort -cu "$dir/modules-list.txt"
while IFS= read -r module; do
  case "$module" in
    ""|/*|../*|*/../*|*/..)
      echo "unsafe module path in modules-list.txt: $module" >&2
      exit 1
      ;;
  esac
  [[ "$module" == *.ko ]] || {
    echo "non-module path in modules-list.txt: $module" >&2
    exit 1
  }
  test -f "$dir/modules/$module" || {
    echo "listed module is missing: $module" >&2
    exit 1
  }
done <"$dir/modules-list.txt"
find "$dir/modules" -type f -name '*.ko' -printf '%P\n' |
  LC_ALL=C sort >"$actual_modules"
cmp -s "$dir/modules-list.txt" "$actual_modules" || {
  echo "module directory differs from modules-list.txt" >&2
  diff -u "$dir/modules-list.txt" "$actual_modules" >&2 || true
  exit 1
}
module_count=$(wc -l <"$dir/modules-list.txt")
module_config_count=$(grep -c '=m$' "$dir/config" || true)
if (( module_config_count > 0 && module_count == 0 )); then
  echo ".config enables $module_config_count modular options but artifact has no .ko files" >&2
  exit 1
fi
if (( module_count > 0 )); then
  (cd "$dir" && sha256sum -c modules-SHA256SUMS)
elif [[ -s "$dir/modules-SHA256SUMS" ]]; then
  echo "module checksum manifest is non-empty for an empty module set" >&2
  exit 1
fi
echo "verified kernel modules: $module_count (modular config entries: $module_config_count)"
if command -v file >/dev/null 2>&1; then
  file "$dir/Image" "$dir/Image.lz4"
else
  echo "file(1) unavailable; payload integrity verified by SHA256SUMS"
fi
sed -n '1,120p' "$dir/build-metadata.txt"

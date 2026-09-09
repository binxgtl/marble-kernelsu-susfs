#!/usr/bin/env bash
set -euo pipefail

root=${1:-work}
lock_file=${LOCK_FILE:-manifests/sources.lock}
source_dir="$root/common"

field() {
  local name=$1 column=$2
  awk -F '|' -v name="$name" -v column="$column" '$1 == name { print $column; exit }' "$lock_file"
}

url=$(field ack-common 3)
commit=$(field ack-common 5)

if [[ -z "$url" || ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
  echo "invalid ACK entry in $lock_file" >&2
  exit 2
fi

mkdir -p "$root"
if [[ ! -d "$source_dir/.git" ]]; then
  git init "$source_dir"
  git -C "$source_dir" remote add origin "$url"
fi

git -C "$source_dir" fetch --depth=1 --no-tags origin "$commit"
git -C "$source_dir" checkout --detach "$commit"
test "$(git -C "$source_dir" rev-parse HEAD)" = "$commit"

version=$(make -s -C "$source_dir" kernelversion)
test "$version" = "5.10.236"
printf 'ACK %s (%s)\n' "$commit" "$version"

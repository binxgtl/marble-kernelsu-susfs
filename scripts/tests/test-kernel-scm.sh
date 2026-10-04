#!/usr/bin/env bash
set -euo pipefail

project=$(cd "$(dirname "$0")/../.." && pwd)
setlocalversion=$(realpath "${1:?usage: test-kernel-scm.sh EXACT_ACK_SETLOCALVERSION}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/source" "$tmp/out/include/config"
git -c init.defaultBranch=main init -q "$tmp/source"
printf 'baseline\n' >"$tmp/source/file"
git -C "$tmp/source" add file
git -C "$tmp/source" -c user.name=test -c user.email=test@example.invalid \
  -c commit.gpgsign=false commit -qm baseline
sha=$(git -C "$tmp/source" rev-parse HEAD)
printf 'patched\n' >"$tmp/source/file"
printf 'CONFIG_LOCALVERSION_AUTO=y\nCONFIG_LOCALVERSION=""\n' >"$tmp/out/include/config/auto.conf"
original=$(cd "$tmp/out" && bash "$setlocalversion" "$tmp/source")
[[ "$original" == *-dirty ]]
printf 'ack-common|test|unused|unused|%s|test\n' "$sha" >"$tmp/lock"
LOCK_FILE="$tmp/lock" bash "$project/scripts/pin-kernel-scm.sh" "$tmp/source"
result=$(cd "$tmp/out" && bash "$setlocalversion" "$tmp/source")
test "$result" = "-g${sha:0:12}"
test -n "$(git -C "$tmp/source" status --porcelain --untracked-files=no)"
printf 'unexpected\n' >"$tmp/source/.scmversion"
if LOCK_FILE="$tmp/lock" bash "$project/scripts/pin-kernel-scm.sh" "$tmp/source" >/dev/null 2>&1; then
  echo 'unexpected SCM override was accepted' >&2
  exit 1
fi
echo 'Exact ACK setlocalversion regression passed; source modifications remain visible'

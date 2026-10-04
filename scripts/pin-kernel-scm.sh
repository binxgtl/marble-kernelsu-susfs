#!/usr/bin/env bash
set -euo pipefail

source_dir=${1:?usage: pin-kernel-scm.sh ACK_SOURCE}
lock_file=${LOCK_FILE:-manifests/sources.lock}
expected=$(awk -F '|' '$1 == "ack-common" {print $5; exit}' "$lock_file")
[[ "$expected" =~ ^[0-9a-f]{40}$ ]]
actual=$(git -C "$source_dir" rev-parse HEAD)
test "$actual" = "$expected"
suffix="-g${actual:0:12}"
scm_file="$source_dir/.scmversion"
if [[ -e "$scm_file" ]]; then
  test "$(cat "$scm_file")" = "$suffix" || {
    echo 'refusing an unexpected existing SCM version override' >&2
    exit 1
  }
else
  printf '%s\n' "$suffix" >"$scm_file"
fi
printf 'Pinned kernel SCM suffix: %s; integration modifications remain recorded separately\n' "$suffix"

#!/bin/sh
set -eu
usage() { echo "Usage: $0 SNAPSHOT TARGET [--confirm-overwrite]"; }
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  usage >&2
  exit 2
fi
SNAPSHOT=$1; TARGET=$2; CONFIRM=${3:-}
case "$SNAPSHOT" in latest|'') echo 'ERROR: select an explicit snapshot ID; latest is forbidden' >&2; exit 1 ;; esac
[ -d "$TARGET" ] || { echo "ERROR: target directory must already exist" >&2; exit 1; }
if [ -n "$(find "$TARGET" -mindepth 1 -maxdepth 1 -print -quit)" ] && [ "$CONFIRM" != --confirm-overwrite ]; then
  echo 'ERROR: target is non-empty; inspect it, then pass --confirm-overwrite' >&2; exit 1
fi
restic snapshots "$SNAPSHOT" >/dev/null
restic restore "$SNAPSHOT" --target "$TARGET"

#!/bin/sh
set -eu
usage() { echo "Usage: $0 SNAPSHOT TARGET [--confirm-overwrite]"; }
[ "$#" -ge 2 ] && [ "$#" -le 3 ] || { usage >&2; exit 2; }
SNAPSHOT=$1; TARGET=$2; CONFIRM=${3:-}
case "$SNAPSHOT" in latest|'') echo 'ERROR: select an explicit snapshot ID; latest is forbidden' >&2; exit 1 ;; esac
[ -d "$TARGET" ] || { echo "ERROR: target directory must already exist" >&2; exit 1; }
if [ -n "$(find "$TARGET" -mindepth 1 -maxdepth 1 -print -quit)" ] && [ "$CONFIRM" != --confirm-overwrite ]; then
  echo 'ERROR: target is non-empty; inspect it, then pass --confirm-overwrite' >&2; exit 1
fi
restic snapshot "$SNAPSHOT" >/dev/null
restic restore "$SNAPSHOT" --target "$TARGET"


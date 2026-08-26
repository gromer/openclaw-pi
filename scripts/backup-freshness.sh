#!/bin/sh
set -eu
MAX_HOURS=${RESTIC_MAX_BACKUP_AGE_HOURS:-36}
latest=$(restic snapshots --json --latest 1 | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d[0]["time"] if d else "")')
[ -n "$latest" ] || { echo 'no Restic snapshots found' >&2; exit 1; }
python3 - "$latest" "$MAX_HOURS" <<'PY'
import datetime, sys
t=datetime.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00'))
age=(datetime.datetime.now(datetime.timezone.utc)-t).total_seconds()/3600
print(f"latest backup age: {age:.1f} hours")
raise SystemExit(age > float(sys.argv[2]))
PY


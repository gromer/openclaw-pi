#!/bin/sh
set -eu

repo_root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repo_root"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/openclaw-preservation.XXXXXX")
cleanup() {
  rm -rf "$test_root"
  rm -f "$test_root.before" "$test_root.after"
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$test_root/.openclaw/workspace"
mkdir -p "$test_root/.config/openclaw/secrets"
cat > "$test_root/.openclaw/openclaw.json" <<'EOF'
{
  "gateway": {"auth": {"token": {"source": "file", "provider": "gateway", "id": "/TOKEN"}}},
  "agents": {"list": [{"id": "existing-agent", "model": {"primary": "existing/provider-model"}}]},
  "models": {"providers": {"existing": {"baseUrl": "https://example.invalid/v1"}}},
  "plugins": {"entries": {"existing-plugin": {"enabled": true}}},
  "channels": {"telegram": {"enabled": true}},
  "marker": "preserve-exact-config-bytes"
}
EOF
cat > "$test_root/.openclaw/workspace/AGENTS.md" <<'EOF'
Existing agent instructions must remain byte-for-byte unchanged.
EOF
cat > "$test_root/.openclaw/workspace/SOUL.md" <<'EOF'
Existing agent behavior must remain byte-for-byte unchanged.
EOF
cat > "$test_root/.openclaw/workspace/TOOLS.md" <<'EOF'
Existing tool guidance must remain byte-for-byte unchanged.
EOF
python3 - "$test_root/.openclaw/runtime-state.sqlite3" <<'PY'
import sqlite3
import sys

connection = sqlite3.connect(sys.argv[1])
connection.execute("CREATE TABLE marker (value TEXT NOT NULL)")
connection.execute("INSERT INTO marker VALUES ('synthetic fixture only')")
connection.commit()
connection.close()
PY
cat > "$test_root/.openclaw/device-identity.fixture" <<'EOF'
Device identity placeholder; this is a test fixture.
EOF
cat > "$test_root/.config/openclaw/secrets/gateway-token.json" <<'EOF'
{"fixture-marker":"not-a-credential"}
EOF
cat > "$test_root/.config/openclaw/secrets/firecrawl.env" <<'EOF'
TEST_FIXTURE=not-a-credential
EOF

snapshot() {
  python3 - "$test_root" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
for path in sorted(p for p in root.rglob("*") if p.is_file()):
    relative = path.relative_to(root).as_posix()
    print(f"{relative} {hashlib.sha256(path.read_bytes()).hexdigest()}")
PY
}

snapshot > "$test_root.before"
OPENCLAW_PRESERVATION_TEST_ROOT=$test_root \
  ansible-playbook -i localhost, tests/config-preservation.yml
snapshot > "$test_root.after"
cmp "$test_root.before" "$test_root.after"

mkdir -p "$test_root/symlink-case/.openclaw"
printf '%s\n' 'manually managed target fixture' > "$test_root/symlink-case/config-target.json"
ln -s missing-target.json "$test_root/symlink-case/.openclaw/openclaw.json"
if OPENCLAW_PRESERVATION_TEST_ROOT="$test_root/symlink-case" \
  ansible-playbook -i localhost, tests/config-preservation.yml >/dev/null 2>&1; then
  echo "configuration seeding accepted a symlink path" >&2
  exit 1
fi
[ -L "$test_root/symlink-case/.openclaw/openclaw.json" ]
[ "$(cat "$test_root/symlink-case/config-target.json")" = 'manually managed target fixture' ]
echo "existing config and runtime fixture preservation: ok"

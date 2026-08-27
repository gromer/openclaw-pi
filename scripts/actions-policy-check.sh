#!/bin/sh
set -eu

status=0
for workflow in .github/workflows/*.yml; do
  while IFS= read -r line; do
    ref=${line##*@}
    ref=${ref%% *}
    if ! printf '%s\n' "$ref" | grep -Eq '^[0-9a-fA-F]{40}$'; then
      echo "un-pinned action in $workflow: $line" >&2
      status=1
    fi
  done <<EOF
$(grep -E '^[[:space:]]*-[[:space:]]+uses:' "$workflow" || true)
EOF
done
if grep -Rqs 'runs-on: ubuntu-latest' .github/workflows; then
  echo 'mutable ubuntu-latest runner found' >&2
  status=1
fi
if ! grep -RqsE '^FROM[[:space:]]+[^[:space:]]+@sha256:[0-9a-f]{64}' roles --include='Dockerfile'; then
  echo 'Dockerfile base image is not digest pinned' >&2
  status=1
fi
exit "$status"

#!/bin/sh
set -eu
for cmd in ansible-playbook ansible-inventory python3; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "missing required command: $cmd" >&2; exit 1; }
done
test -f ansible.cfg && test -f playbooks/site.yml
echo "preflight: ok"


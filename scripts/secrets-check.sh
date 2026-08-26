#!/bin/sh
set -eu
status=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then files=$(git ls-files); else files=$(find . -type f -not -path './.git/*'); fi
printf '%s\n' "$files" | grep -E '(age-identity|\.agekey$|\.dec\.ya?ml$|secrets\.plain)' && { echo 'forbidden secret filename tracked' >&2; status=1; } || true
pattern='(BEGIN (OPENSSH|RSA|EC) PRIVATE KEY|AGE-SECRET'"'-KEY-'"'|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,})'
printf '%s\n' "$files" | xargs grep -IEn "$pattern" 2>/dev/null && { echo 'probable plaintext secret found' >&2; status=1; } || true
exit "$status"

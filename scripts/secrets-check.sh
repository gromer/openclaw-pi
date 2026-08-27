#!/bin/sh
set -eu
status=0
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then files=$(git ls-files); else files=$(find . -type f -not -path './.git/*'); fi
if printf '%s\n' "$files" | grep -E '(^|/)(age-identity(\.txt)?|sops-age-keys\.txt|secrets\.plain(\.ya?ml)?)$|\.agekey$|\.dec\.ya?ml$'; then
  echo 'forbidden secret filename tracked' >&2
  status=1
fi
pattern='(BEGIN (OPENSSH|RSA|EC) PRIVATE KEY|AGE-SECRET'"'-KEY-'"'|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{30,})'
if printf '%s\n' "$files" | xargs grep -IEn "$pattern" 2>/dev/null; then
  echo 'probable plaintext secret found' >&2
  status=1
fi
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then sh_files=$(git ls-files '*.sh'); else sh_files=$(find . -type f -name '*.sh' -not -path './.git/*'); fi
xtrace_pattern='set([[:space:]]|$).*(-o[[:space:]]+xtrace|-[a-zA-Z]*x[a-zA-Z]*)'
if [ -n "$sh_files" ] && {
  printf '%s\n' "$sh_files" | xargs grep -En "^[[:space:]]*$xtrace_pattern" 2>/dev/null ||
  printf '%s\n' "$sh_files" | xargs grep -En "[;&|][[:space:]]*$xtrace_pattern" 2>/dev/null;
}; then
  echo 'forbidden shell xtrace can leak secrets to logs' >&2
  status=1
fi
exit "$status"

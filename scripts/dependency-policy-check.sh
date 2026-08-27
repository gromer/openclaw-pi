#!/bin/sh
set -eu

status=0
requirements=.github/requirements-ci.txt
while IFS= read -r requirement; do
  case "$requirement" in
    ''|'#'*) continue ;;
    *'=='*) ;;
    *) echo "un-pinned CI dependency: $requirement" >&2; status=1 ;;
  esac
done < "$requirements"
exit "$status"

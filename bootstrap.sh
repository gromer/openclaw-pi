#!/bin/sh
set -eu
umask 077

REPO_URL=${OPENCLAW_PI_REPO_URL:-https://github.com/OWNER/openclaw-pi.git}
REPO_REF=${OPENCLAW_PI_REF:-}
DEST=${OPENCLAW_PI_DEST:-/opt/openclaw-pi}
INVENTORY=${OPENCLAW_PI_INVENTORY:-}
MODE=provision

usage() {
  cat <<'EOF'
Usage: sudo OPENCLAW_PI_REPO_URL=URL OPENCLAW_PI_REF=TAG_OR_SHA sh bootstrap.sh [OPTIONS]
  --validate-only  Clone/update and run validation, but do not provision
  --dry-run        Run Ansible check/diff mode
  --help           Show this help

Secrets are never accepted as flags. Configure an age identity out-of-band and
put encrypted values in the production inventory.
EOF
}
while [ "$#" -gt 0 ]; do
  case "$1" in
    --validate-only) MODE=validate ;;
    --dry-run) MODE=dry-run ;;
    --help) usage; exit 0 ;;
    *) echo "ERROR: unexpected argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo/root" >&2; exit 1; }
[ -n "$REPO_REF" ] || { echo "ERROR: OPENCLAW_PI_REF must be an immutable tag or commit" >&2; exit 1; }
case "$REPO_REF" in main|master|develop|latest|HEAD) echo "ERROR: mutable repository ref rejected" >&2; exit 1 ;; esac
[ -r /etc/os-release ] || { echo "ERROR: /etc/os-release missing" >&2; exit 1; }
. /etc/os-release
[ "${ID:-}" = raspbian ] || [ "${ID_LIKE:-}" = debian ] || { echo "ERROR: Raspberry Pi OS required" >&2; exit 1; }
[ "$(uname -m)" = aarch64 ] || { echo "ERROR: 64-bit ARM (aarch64) required" >&2; exit 1; }
grep -Eq 'Raspberry Pi 5|BCM2712' /proc/device-tree/model /proc/cpuinfo 2>/dev/null || { echo "ERROR: Raspberry Pi 5 hardware not detected" >&2; exit 1; }
[ "$(df -Pk / | awk 'NR==2 {print $4}')" -ge 4194304 ] || { echo "ERROR: at least 4 GiB free disk space required" >&2; exit 1; }
getent hosts github.com >/dev/null 2>&1 || { echo "ERROR: DNS/network check failed" >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends git ansible-core ca-certificates curl make
case "$REPO_URL" in https://*|ssh://*|git@*:*) ;; *) echo "ERROR: repository URL must use HTTPS or SSH" >&2; exit 1 ;; esac
if [ -d "$DEST/.git" ]; then
  git -C "$DEST" fetch --tags --prune origin
else
  [ ! -e "$DEST" ] || { echo "ERROR: destination exists but is not a Git checkout: $DEST" >&2; exit 1; }
  git clone --filter=blob:none "$REPO_URL" "$DEST"
fi
git -C "$DEST" checkout --detach "$REPO_REF"
case "$MODE" in
  validate) make -C "$DEST" preflight validate ;;
  dry-run)
    [ -f "$INVENTORY" ] || { echo "ERROR: set OPENCLAW_PI_INVENTORY to a pre-staged production hosts.yml" >&2; exit 1; }
    make -C "$DEST" preflight diff INVENTORY="$INVENTORY" ;;
  provision)
    [ -f "$INVENTORY" ] || { echo "ERROR: set OPENCLAW_PI_INVENTORY to a pre-staged production hosts.yml" >&2; exit 1; }
    make -C "$DEST" preflight provision INVENTORY="$INVENTORY" ;;
esac
echo "OpenClaw Pi bootstrap completed at $DEST"

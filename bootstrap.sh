#!/bin/sh
set -eu
umask 077

RELEASE=${OPENCLAW_PI_RELEASE:-}
REPOSITORY=${OPENCLAW_PI_REPOSITORY:-gromer/openclaw-pi}
ASSET_BASE_URL=${OPENCLAW_PI_ASSET_BASE_URL:-}
DEST_ROOT=${OPENCLAW_PI_DEST:-/opt/openclaw-pi}
INVENTORY=${OPENCLAW_PI_INVENTORY:-}
MODE=provision
STAGING_DIR=
TEMP_LINK=

usage() {
  cat <<'EOF'
Usage: sudo OPENCLAW_PI_RELEASE=TAG sh bootstrap.sh [OPTIONS]
  --validate-only  Validate the downloaded release without provisioning
  --dry-run        Run Ansible check/diff mode without applying changes
  --help           Show this help

Environment:
  OPENCLAW_PI_RELEASE        Required immutable release tag, for example v1.1.0
  OPENCLAW_PI_REPOSITORY     GitHub OWNER/REPO (default: gromer/openclaw-pi)
  OPENCLAW_PI_ASSET_BASE_URL Optional HTTPS release-asset mirror URL
  OPENCLAW_PI_DEST           Install root (default: /opt/openclaw-pi)
  OPENCLAW_PI_INVENTORY      Production hosts.yml; required except validation-only

Secrets are never accepted as flags. Configure an age identity out-of-band and
put encrypted values in the production inventory.
EOF
}

cleanup() {
  if [ -n "$TEMP_LINK" ]; then
    rm -f "$TEMP_LINK"
  fi
  if [ -n "$STAGING_DIR" ] && [ -d "$STAGING_DIR" ]; then
    rm -rf "$STAGING_DIR"
  fi
}
trap cleanup EXIT HUP INT TERM

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
[ -n "$RELEASE" ] || { echo "ERROR: OPENCLAW_PI_RELEASE is required" >&2; exit 1; }
case "$RELEASE" in
  *[!A-Za-z0-9._-]*|main|master|develop|latest|HEAD)
    echo "ERROR: release must be an immutable tag using only letters, numbers, dot, underscore, and dash" >&2
    exit 1
    ;;
esac
case "$REPOSITORY" in
  */*) ;;
  *)
    echo "ERROR: OPENCLAW_PI_REPOSITORY must be in the form OWNER/REPO" >&2
    exit 1
    ;;
esac
REPOSITORY_OWNER=${REPOSITORY%%/*}
REPOSITORY_NAME=${REPOSITORY#*/}
case "$REPOSITORY_OWNER/$REPOSITORY_NAME" in
  *[!A-Za-z0-9._/-]*|/*|*/|*/*/*)
    echo "ERROR: OPENCLAW_PI_REPOSITORY must be a safe OWNER/REPO slug" >&2
    exit 1
    ;;
esac
case "$DEST_ROOT" in
  /*) ;;
  *) echo "ERROR: OPENCLAW_PI_DEST must be an absolute path" >&2; exit 1 ;;
esac
case "$DEST_ROOT" in
  /|/opt|/usr|/var|/root|/home) echo "ERROR: refusing unsafe install root: $DEST_ROOT" >&2; exit 1 ;;
esac
if [ -z "$ASSET_BASE_URL" ]; then
  ASSET_BASE_URL="https://github.com/${REPOSITORY}/releases/download/${RELEASE}"
fi
case "$ASSET_BASE_URL" in
  https://*) ;;
  *) echo "ERROR: release asset URL must use HTTPS" >&2; exit 1 ;;
esac
ASSET_BASE_URL=${ASSET_BASE_URL%/}

[ -r /etc/os-release ] || { echo "ERROR: /etc/os-release missing" >&2; exit 1; }
# shellcheck disable=SC1091
. /etc/os-release
case " ${ID:-} ${ID_LIKE:-} " in
  *" debian "*|*" raspbian "*) ;;
  *)
    echo "ERROR: Raspberry Pi OS (Debian family) required" >&2
    exit 1
    ;;
esac
[ "$(uname -m)" = aarch64 ] || { echo "ERROR: 64-bit ARM (aarch64) required" >&2; exit 1; }
grep -Eq 'Raspberry Pi 5|BCM2712' /proc/device-tree/model /proc/cpuinfo 2>/dev/null || {
  echo "ERROR: Raspberry Pi 5 hardware not detected" >&2
  exit 1
}
[ "$(df -Pk / | awk 'NR==2 {print $4}')" -ge 4194304 ] || {
  echo "ERROR: at least 4 GiB free disk space required" >&2
  exit 1
}

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ansible-core ca-certificates curl make tar

install -d -m 0755 "$DEST_ROOT" "$DEST_ROOT/releases"
STAGING_DIR=$(mktemp -d "$DEST_ROOT/.staging.XXXXXX")
ARCHIVE_NAME="openclaw-pi-${RELEASE}.tar.gz"
ARCHIVE_PATH="$STAGING_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"

echo "Downloading release bundle $RELEASE from $ASSET_BASE_URL"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  --output "$ARCHIVE_PATH" "$ASSET_BASE_URL/$ARCHIVE_NAME"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  --output "$CHECKSUM_PATH" "$ASSET_BASE_URL/$ARCHIVE_NAME.sha256"
(
  cd "$STAGING_DIR"
  sha256sum --check "$ARCHIVE_NAME.sha256"
)

ARCHIVE_PREFIX="openclaw-pi-${RELEASE}/"
tar -tzf "$ARCHIVE_PATH" >/dev/null
if ! tar -tzf "$ARCHIVE_PATH" | awk -v prefix="$ARCHIVE_PREFIX" '
  index($0, prefix) != 1 || $0 ~ /(^|\/)\.\.($|\/)/ || $0 ~ /^\// { bad = 1 }
  END { exit bad }
'; then
  echo "ERROR: archive contains an invalid or unexpected path" >&2
  exit 1
fi
if ! tar -tvzf "$ARCHIVE_PATH" | awk '$1 ~ /^[lh]/ { bad = 1 } END { exit bad }'; then
  echo "ERROR: archive contains unsupported symbolic or hard links" >&2
  exit 1
fi

tar --extract --gzip --file "$ARCHIVE_PATH" --directory "$STAGING_DIR" \
  --no-same-owner --no-same-permissions
EXTRACTED_DIR="$STAGING_DIR/openclaw-pi-${RELEASE}"
[ -f "$EXTRACTED_DIR/playbooks/site.yml" ] || { echo "ERROR: release bundle is incomplete" >&2; exit 1; }
[ -f "$EXTRACTED_DIR/Makefile" ] || { echo "ERROR: release bundle has no Makefile" >&2; exit 1; }
EXPECTED_SHA256=$(awk 'NR == 1 { print $1 }' "$CHECKSUM_PATH")
RELEASE_DIR="$DEST_ROOT/releases/$RELEASE"

if [ -e "$RELEASE_DIR" ]; then
  [ -d "$RELEASE_DIR" ] || { echo "ERROR: release path exists and is not a directory" >&2; exit 1; }
  [ -r "$RELEASE_DIR/.release-archive.sha256" ] || {
    echo "ERROR: existing release has no checksum marker; refusing to overwrite it" >&2
    exit 1
  }
  INSTALLED_SHA256=$(sed -n '1p' "$RELEASE_DIR/.release-archive.sha256")
  [ "$INSTALLED_SHA256" = "$EXPECTED_SHA256" ] || {
    echo "ERROR: existing release checksum differs; refusing to overwrite immutable release" >&2
    exit 1
  }
else
  printf '%s\n' "$EXPECTED_SHA256" > "$EXTRACTED_DIR/.release-archive.sha256"
  chmod 0444 "$EXTRACTED_DIR/.release-archive.sha256"
  mv "$EXTRACTED_DIR" "$RELEASE_DIR"
fi

if [ -e "$DEST_ROOT/current" ] && [ ! -L "$DEST_ROOT/current" ]; then
  echo "ERROR: $DEST_ROOT/current exists and is not a symbolic link" >&2
  exit 1
fi
TEMP_LINK="$DEST_ROOT/.current.$$"
ln -s "releases/$RELEASE" "$TEMP_LINK"
mv -Tf "$TEMP_LINK" "$DEST_ROOT/current"
TEMP_LINK=
RUN_DIR="$DEST_ROOT/current"

case "$MODE" in
  validate)
    make -C "$RUN_DIR" preflight syntax
    sh -n "$RUN_DIR/bootstrap.sh" "$RUN_DIR"/scripts/*.sh
    python3 "$RUN_DIR/scripts/validate-vars.py"
    python3 "$RUN_DIR/tests/test_static.py"
    (cd "$RUN_DIR" && ./scripts/secrets-check.sh)
    ;;
  dry-run)
    [ -f "$INVENTORY" ] || {
      echo "ERROR: set OPENCLAW_PI_INVENTORY to a pre-staged production hosts.yml" >&2
      exit 1
    }
    make -C "$RUN_DIR" preflight diff INVENTORY="$INVENTORY"
    ;;
  provision)
    [ -f "$INVENTORY" ] || {
      echo "ERROR: set OPENCLAW_PI_INVENTORY to a pre-staged production hosts.yml" >&2
      exit 1
    }
    make -C "$RUN_DIR" preflight provision INVENTORY="$INVENTORY"
    ;;
esac
echo "OpenClaw Pi bootstrap completed from $RUN_DIR"

#!/bin/sh
set -eu
umask 077

REPOSITORY=${OPENCLAW_PI_REPOSITORY:-gromer/openclaw-pi}
RELEASE=${OPENCLAW_PI_RELEASE:-}
DEST_ROOT=${OPENCLAW_PI_DEST:-/opt/openclaw-pi}
INVENTORY_DIR=${OPENCLAW_PI_INVENTORY_DIR:-/root/openclaw-inventory}
SOPS_VERSION=${OPENCLAW_PI_SOPS_VERSION:-3.13.3}
AGE_KEY_FILE=${SOPS_AGE_KEY_FILE:-/root/.config/sops/age/keys.txt}
TEMP_DIR=

usage() {
  cat <<'EOF'
Usage: sudo sh install.sh

Interactive first-run installer for an Ollama-backed OpenClaw Pi gateway. It
resolves the latest GitHub release to a concrete tag, creates a protected local
inventory when needed, and invokes the checksum-verifying release bootstrap.

Environment:
  OPENCLAW_PI_RELEASE       Optional release tag instead of latest
  OPENCLAW_PI_REPOSITORY    GitHub OWNER/REPO (default: gromer/openclaw-pi)
  OPENCLAW_PI_DEST          Install root (default: /opt/openclaw-pi)
  OPENCLAW_PI_INVENTORY_DIR Inventory root (default: /root/openclaw-inventory)
  OPENCLAW_PI_SOPS_VERSION  Pinned SOPS version (default: 3.13.3)
  SOPS_AGE_KEY_FILE         age identity path

Secrets are generated locally and are never accepted as arguments or printed.
EOF
}

cleanup() {
  if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT HUP INT TERM

[ "$#" -eq 0 ] || {
  [ "$#" -eq 1 ] && [ "$1" = --help ] && { usage; exit 0; }
  echo "ERROR: unexpected argument" >&2
  usage >&2
  exit 2
}
[ "$(id -u)" -eq 0 ] || { echo "ERROR: run with sudo/root" >&2; exit 1; }
[ -r /dev/tty ] || { echo "ERROR: an interactive terminal is required" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required to start the installer" >&2; exit 1; }

case "$REPOSITORY" in
  */*) ;;
  *) echo "ERROR: OPENCLAW_PI_REPOSITORY must be in the form OWNER/REPO" >&2; exit 1 ;;
esac
repository_owner=${REPOSITORY%%/*}
repository_name=${REPOSITORY#*/}
case "$repository_owner/$repository_name" in
  *[!A-Za-z0-9._/-]*|/*|*/|*/*/*)
    echo "ERROR: OPENCLAW_PI_REPOSITORY must be a safe OWNER/REPO slug" >&2
    exit 1
    ;;
esac
case "$SOPS_VERSION" in
  ''|*[!0-9.]*|.*|*.) echo "ERROR: OPENCLAW_PI_SOPS_VERSION is invalid" >&2; exit 1 ;;
esac
for path in "$DEST_ROOT" "$INVENTORY_DIR" "$AGE_KEY_FILE"; do
  case "$path" in
    /*) ;;
    *) echo "ERROR: installer paths must be absolute" >&2; exit 1 ;;
  esac
done
case "$INVENTORY_DIR" in
  /|/root|/etc|/usr|/var|/opt|/home)
    echo "ERROR: refusing unsafe inventory directory: $INVENTORY_DIR" >&2
    exit 1
    ;;
esac

if [ -z "$RELEASE" ]; then
  echo "Resolving the latest published release for $REPOSITORY"
  RELEASE_URL=$(curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --output /dev/null --write-out '%{url_effective}' \
    "https://github.com/$REPOSITORY/releases/latest")
  RELEASE=${RELEASE_URL##*/}
fi
case "$RELEASE" in
  ''|*[!A-Za-z0-9._-]*|main|master|develop|latest|HEAD)
    echo "ERROR: GitHub did not resolve a safe release tag" >&2
    exit 1
    ;;
esac
echo "Selected release tag: $RELEASE"

TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/openclaw-pi-install.XXXXXX")
ASSET_URL="https://github.com/$REPOSITORY/releases/download/$RELEASE"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  --output "$TEMP_DIR/bootstrap.sh" "$ASSET_URL/bootstrap.sh"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  --output "$TEMP_DIR/bootstrap.sh.sha256" "$ASSET_URL/bootstrap.sh.sha256"
(
  cd "$TEMP_DIR"
  sha256sum --check bootstrap.sh.sha256
)

OPENCLAW_PI_RELEASE=$RELEASE \
OPENCLAW_PI_REPOSITORY=$REPOSITORY \
OPENCLAW_PI_DEST=$DEST_ROOT \
  sh "$TEMP_DIR/bootstrap.sh" --validate-only

HOSTS_FILE=$INVENTORY_DIR/hosts.yml
ALL_FILE=$INVENTORY_DIR/group_vars/all.yml
SECRETS_FILE=$INVENTORY_DIR/group_vars/secrets.sops.yml
existing=0
for path in "$HOSTS_FILE" "$ALL_FILE" "$SECRETS_FILE"; do
  [ -e "$path" ] && existing=$((existing + 1))
done
if [ "$existing" -ne 0 ] && [ "$existing" -ne 3 ]; then
  echo "ERROR: inventory is incomplete; expected all three files under $INVENTORY_DIR" >&2
  exit 1
fi

if [ "$existing" -eq 0 ]; then
  echo
  echo "Creating a new local Ollama inventory. Press Enter to accept defaults."

  default_admin=${SUDO_USER:-}
  if [ -z "$default_admin" ] || [ "$default_admin" = root ]; then
    default_admin=$(getent passwd 1000 | awk -F: 'NR == 1 { print $1 }')
  fi
  printf 'Administrative user [%s]: ' "$default_admin" >/dev/tty
  IFS= read -r admin_user </dev/tty
  admin_user=${admin_user:-$default_admin}
  case "$admin_user" in
    ''|*[!a-z0-9_-]*|[0-9]*|-*) echo "ERROR: invalid administrative user" >&2; exit 1 ;;
  esac

  default_key=
  if [ -r "/home/$admin_user/.ssh/authorized_keys" ]; then
    default_key=$(awk '!/^([[:space:]]*#|[[:space:]]*$)/ { print; exit }' \
      "/home/$admin_user/.ssh/authorized_keys")
  fi
  if [ -n "$default_key" ]; then
    echo "Using the first authorized SSH key already installed for $admin_user."
    ssh_key=$default_key
  else
    printf 'Paste an SSH public key: ' >/dev/tty
    IFS= read -r ssh_key </dev/tty
  fi
  if ! printf '%s\n' "$ssh_key" | grep -Eq \
    '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh.com) [A-Za-z0-9+/=]+( [A-Za-z0-9._@+-]+)?$'; then
    echo "ERROR: SSH key must be a supported public key with an optional simple comment" >&2
    exit 1
  fi

  printf 'Ollama base URL (for example http://mac-mini.local:11434): ' >/dev/tty
  IFS= read -r ollama_url </dev/tty
  ollama_url=${ollama_url%/}
  if ! printf '%s\n' "$ollama_url" | grep -Eq '^https?://[A-Za-z0-9._-]+(:[0-9]{1,5})?$'; then
    echo "ERROR: enter an HTTP(S) Ollama origin without a path" >&2
    exit 1
  fi
  inference_host=${ollama_url#*://}
  inference_host=${inference_host%%:*}

  curl --fail --silent --show-error --max-time 10 "$ollama_url/api/tags" \
    --output "$TEMP_DIR/ollama-tags.json" || {
      echo "ERROR: the Pi cannot reach $ollama_url/api/tags" >&2
      exit 1
    }
  printf 'Ollama model (exact name and tag): ' >/dev/tty
  IFS= read -r ollama_model </dev/tty
  case "$ollama_model" in
    ''|*[!A-Za-z0-9._:/+-]*) echo "ERROR: invalid Ollama model name" >&2; exit 1 ;;
  esac

  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y --no-install-recommends age ca-certificates jq openssl
  jq --exit-status --arg model "$ollama_model" \
    '.models[] | select(.name == $model or .model == $model)' \
    "$TEMP_DIR/ollama-tags.json" >/dev/null || {
      echo "ERROR: Ollama does not advertise model $ollama_model" >&2
      exit 1
    }

  sops_binary="sops-v${SOPS_VERSION}.linux.arm64"
  sops_url="https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --output "$TEMP_DIR/$sops_binary" "$sops_url/$sops_binary"
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --output "$TEMP_DIR/sops.checksums.txt" "$sops_url/sops-v${SOPS_VERSION}.checksums.txt"
  (
    cd "$TEMP_DIR"
    checksum_line=$(awk -v bin="$sops_binary" '$2 == bin { print; found++ } END { if (found != 1) exit 1 }' sops.checksums.txt) || {
      echo "ERROR: missing or non-unique checksum entry for $sops_binary" >&2
      exit 1
    }
    printf '%s\n' "$checksum_line" | sha256sum --check -
  )
  install -o root -g root -m 0755 "$TEMP_DIR/$sops_binary" /usr/local/bin/sops

  install -d -o root -g root -m 0700 "$(dirname "$AGE_KEY_FILE")"
  if [ ! -e "$AGE_KEY_FILE" ]; then
    age-keygen -o "$AGE_KEY_FILE" >/dev/null
  fi
  chmod 0600 "$AGE_KEY_FILE"
  age_recipient=$(age-keygen -y "$AGE_KEY_FILE")

  install -d -o root -g root -m 0700 "$INVENTORY_DIR/group_vars"
  cat > "$HOSTS_FILE" <<'EOF'
---
all:
  hosts:
    openclaw-pi:
      ansible_connection: local
      ansible_python_interpreter: /usr/bin/python3
EOF
  awk -v hostname="openclaw-pi" -v admin="$admin_user" -v key="$ssh_key" \
    -v host="$inference_host" -v url="$ollama_url" -v model="$ollama_model" \
    -v secrets="$SECRETS_FILE" '
      /^pi_hostname:/ { print "pi_hostname: " hostname; next }
      /^admin_user:/ { print "admin_user: " admin; next }
      /^admin_ssh_public_keys:/ {
        print
        print "  - \"" key "\""
        skip_key = 1
        next
      }
      skip_key && /^  - / { next }
      { skip_key = 0 }
      /^inference_backend:/ { print "inference_backend: ollama"; next }
      /^inference_host:/ { print "inference_host: \"" host "\""; next }
      /^inference_base_url:/ { print "inference_base_url: \"" url "\""; next }
      /^inference_model:/ { print "inference_model: \"" model "\""; next }
      /^secrets_file:/ { print "secrets_file: \"" secrets "\""; next }
      { print }
    ' "$DEST_ROOT/current/inventories/example/group_vars/all.yml" > "$ALL_FILE"

  gateway_token=$(openssl rand -hex 32)
  searxng_secret_key=$(openssl rand -hex 32)
  encrypted_tmp=$TEMP_DIR/secrets.sops.yml
  printf 'gateway_token: "%s"\nsearxng_secret_key: "%s"\ninference_api_key: ""\nopenrouter_api_key: ""\nrestic_password: ""\nrestic_environment: ""\n' \
    "$gateway_token" "$searxng_secret_key" |
    SOPS_AGE_KEY_FILE=$AGE_KEY_FILE sops --encrypt --age "$age_recipient" \
      --input-type yaml --output-type yaml /dev/stdin > "$encrypted_tmp"
  unset gateway_token searxng_secret_key
  install -o root -g root -m 0600 "$encrypted_tmp" "$SECRETS_FILE"
  chmod 0600 "$HOSTS_FILE" "$ALL_FILE" "$SECRETS_FILE"

  echo
  echo "Generated a new age identity at: $AGE_KEY_FILE"
  echo "Public recovery recipient: $age_recipient"
  echo "Back up the private identity securely after installation. Without it,"
  echo "the encrypted inventory cannot be recovered. The identity is not printed."
else
  echo "Reusing the complete inventory at $INVENTORY_DIR"
  [ -r "$AGE_KEY_FILE" ] || {
    echo "ERROR: existing inventory requires the age identity at $AGE_KEY_FILE" >&2
    exit 1
  }
  admin_user=$(awk -F': *' '/^admin_user:/{print $2; exit}' "$ALL_FILE" 2>/dev/null || true)
  admin_user=${admin_user:-${SUDO_USER:-root}}
fi

SOPS_AGE_KEY_FILE=$AGE_KEY_FILE \
OPENCLAW_PI_RELEASE=$RELEASE \
OPENCLAW_PI_REPOSITORY=$REPOSITORY \
OPENCLAW_PI_DEST=$DEST_ROOT \
OPENCLAW_PI_INVENTORY=$HOSTS_FILE \
  sh "$TEMP_DIR/bootstrap.sh"

echo
echo "Installation complete from $RELEASE."
echo "Inventory: $INVENTORY_DIR"
echo "Verify: systemctl status openclaw docker --no-pager"
echo "Dashboard: http://$(hostname).local:18789 (from the allowed LAN)"

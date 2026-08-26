# Getting started with a fresh Pi and an existing Ollama server

This guide starts with:

- a Raspberry Pi 5 running updated 64-bit Raspberry Pi OS;
- local console or desktop access to the Pi;
- an Ollama server already reachable somewhere on the same trusted network; and
- a separate workstation from which you will administer the Pi.

It ends with a hardened, key-only SSH login, OpenClaw running as a systemd
service, Docker-backed tool sandboxes, and loopback-only SearXNG. No Git checkout
is required on the Pi.

Commands marked **workstation** run on your laptop or desktop. Commands marked
**Pi** run on the Raspberry Pi. Replace every value written as `REPLACE_...`.

## Fast path

After completing the SSH setup in sections 1 and 2, the guided installer can do
the remaining initial configuration. The recommended checksum-verified flow is:

```sh
mkdir -p "$HOME/openclaw-install" && cd "$HOME/openclaw-install"
curl -fsSLO https://github.com/gromer/openclaw-pi/releases/latest/download/install.sh
curl -fsSLO https://github.com/gromer/openclaw-pi/releases/latest/download/install.sh.sha256
sha256sum --check install.sh.sha256
less install.sh
sudo sh install.sh
```

Enter the Ollama origin, such as `http://mac-mini.local:11434`, and the exact
model shown by Ollama. The installer reuses the current account's authorized SSH
key where possible, generates and encrypts local secrets, and provisions the
latest release. Back up `/root/.config/sops/age/keys.txt` securely when it
finishes.

For a convenience-first installation, accepting that network-delivered code is
executed as root before separate checksum inspection:

```sh
curl --proto '=https' --tlsv1.2 -fsSL \
  https://github.com/gromer/openclaw-pi/releases/latest/download/install.sh | sudo sh
```

The rest of this guide remains the fully manual, auditable workflow.

## Before you begin

Record:

- the Pi's current Raspberry Pi OS username;
- the Pi's LAN IP address;
- the DNS name or static/reserved address of the Ollama host;
- the exact Ollama model ID you want OpenClaw to use; and
- where you will keep an offline backup of the age identity.

This guide uses DHCP and assumes the router provides a reservation for the Pi.
It does not expose the OpenClaw dashboard or SearXNG to the LAN. You will reach
the dashboard through an SSH tunnel.

Authoritative references:

- [Raspberry Pi SSH documentation](https://www.raspberrypi.com/documentation/computers/remote-access.html)
- [SOPS installation and verification](https://getsops.io/docs/installation/)
- [SOPS configuration reference](https://getsops.io/docs/reference/)
- [age installation](https://github.com/FiloSottile/age#installation)
- [OpenClaw Ollama provider](https://docs.openclaw.ai/providers/ollama)
- [OpenClaw Pi v1.1.0 release](https://github.com/gromer/openclaw-pi/releases/tag/v1.1.0)

## 1. Enable SSH on the Pi

At the Pi's local console, install the SSH server and basic setup tools:

```sh
sudo apt install -y openssh-server curl jq age nano openssl
sudo raspi-config
```

In `raspi-config`, select **Interface Options → SSH → Yes**, then exit. Confirm
the daemon is enabled and running:

```sh
sudo systemctl enable --now ssh
sudo systemctl status ssh --no-pager
hostname -I
```

Write down the Pi's LAN address. The official Raspberry Pi documentation notes
that SSH is disabled by default unless it was enabled through Raspberry Pi
Imager or the operating-system configuration tools.

## 2. Create an administrator SSH key

On the workstation, first check whether you already have an Ed25519 key:

```sh
test -f "$HOME/.ssh/id_ed25519.pub" && cat "$HOME/.ssh/id_ed25519.pub"
```

If the file does not exist, create a key protected by a strong passphrase:

```sh
ssh-keygen -t ed25519 -a 100 -f "$HOME/.ssh/id_ed25519"
```

Keep `id_ed25519` private. The `.pub` file is intentionally shareable.

Before accepting the Pi's host key for the first time, inspect its fingerprint
at the Pi's local console:

```sh
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
```

Now connect from the workstation using the Pi's existing Raspberry Pi OS user.
Compare the fingerprint shown by SSH with the console value before answering
`yes`:

```sh
ssh-copy-id -i "$HOME/.ssh/id_ed25519.pub" REPLACE_OS_USER@REPLACE_PI_IP
ssh REPLACE_OS_USER@REPLACE_PI_IP
```

Leave this SSH session open until the final `piadmin` login has been tested.
Provisioning disables password authentication and restricts SSH to `piadmin`.

Display the public key on the workstation and keep it ready for the inventory:

```sh
cat "$HOME/.ssh/id_ed25519.pub"
```

## 3. Verify Ollama from the Pi

From the Pi, query the Ollama API using its LAN hostname or address:

```sh
OLLAMA_URL=http://REPLACE_OLLAMA_HOST:11434
curl --fail --silent --show-error "$OLLAMA_URL/api/tags" | jq .
```

Confirm that the selected model appears in the response. Record its exact `name`
value, including any tag such as `:latest`, `:8b`, or `:27b`.

If this request fails, stop here. Check the Ollama listener, host firewall, DNS,
and LAN routing. Do not expose Ollama to the public internet. Ideally, restrict
port 11434 on the Ollama host to the Pi's address.

## 4. Install SOPS on the Pi

The bootstrap runs Ansible locally on the Pi, so SOPS must also be installed on
the Pi. The following installs the current ARM64 release used when this guide was
written. Check the [SOPS releases page](https://github.com/getsops/sops/releases)
for a newer stable release before proceeding.

```sh
cd /tmp
SOPS_VERSION=3.13.3
SOPS_BINARY="sops-v${SOPS_VERSION}.linux.arm64"
SOPS_BASE_URL="https://github.com/getsops/sops/releases/download/v${SOPS_VERSION}"

curl -fsSLO "${SOPS_BASE_URL}/${SOPS_BINARY}"
curl -fsSLO "${SOPS_BASE_URL}/sops-v${SOPS_VERSION}.checksums.txt"
grep "  ${SOPS_BINARY}$" "sops-v${SOPS_VERSION}.checksums.txt" | sha256sum --check -
sudo install -o root -g root -m 0755 "$SOPS_BINARY" /usr/local/bin/sops
sops --version
```

For stronger provenance verification, follow the upstream release instructions
to verify the signed checksum bundle or SLSA provenance before installing the
binary. A checksum downloaded from the same release proves integrity but is not
an independent publisher identity check.

## 5. Create and back up the age identity

Create a root-only identity directory and generate one identity:

```sh
sudo install -d -o root -g root -m 0700 /root/.config/sops/age
sudo age-keygen -o /root/.config/sops/age/keys.txt
sudo chmod 0600 /root/.config/sops/age/keys.txt
sudo age-keygen -y /root/.config/sops/age/keys.txt
```

The last command prints the public recipient beginning with `age1`. Record that
public value. Never copy the private identity line into inventory, Git, terminal
messages, or documentation.

Before provisioning, make at least two encrypted or physically secured offline
backups of `/root/.config/sops/age/keys.txt`. If every copy is lost, the SOPS
file cannot be recovered. Test that the backup can reproduce the same public
recipient.

## 6. Create the production inventory

Create the root-only directory tree on the Pi:

```sh
sudo install -d -o root -g root -m 0700 /root/openclaw-inventory
sudo install -d -o root -g root -m 0700 /root/openclaw-inventory/group_vars
```

Create `/root/openclaw-inventory/hosts.yml`:

```sh
sudoedit /root/openclaw-inventory/hosts.yml
```

Enter:

```yaml
---
all:
  hosts:
    openclaw-pi:
      ansible_connection: local
      ansible_python_interpreter: /usr/bin/python3
```

Create `/root/openclaw-inventory/group_vars/all.yml`:

```sh
sudoedit /root/openclaw-inventory/group_vars/all.yml
```

Enter the following, replacing the SSH key, Ollama host, and model. The SSH value
must be the complete single line from `id_ed25519.pub`:

```yaml
---
pi_hostname: openclaw-pi
pi_network_mode: dhcp
pi_manage_network: false

admin_user: piadmin
admin_groups: [sudo]
admin_ssh_public_keys:
  - "ssh-ed25519 REPLACE_WITH_COMPLETE_PUBLIC_KEY"

openclaw_user: openclaw
openclaw_group: openclaw
openclaw_version: "2026.7.1"
openclaw_state_dir: /var/lib/openclaw
openclaw_workspace_dir: /var/lib/openclaw/workspace
openclaw_config_path: /etc/openclaw/openclaw.json
openclaw_gateway_port: 18789
openclaw_gateway_bind: loopback
node_major: "24"

inference_backend: ollama
inference_host: REPLACE_OLLAMA_HOST
inference_base_url: "http://REPLACE_OLLAMA_HOST:11434"
inference_model: "REPLACE_EXACT_OLLAMA_MODEL"
inference_context_window: 32768
inference_max_tokens: 8192
inference_timeout_seconds: 300

secrets_file: /root/openclaw-inventory/group_vars/secrets.sops.yml

sandbox_mode: all
sandbox_scope: agent
sandbox_workspace_access: none
sandbox_image: openclaw-sandbox:bookworm-slim
sandbox_network: none
sandbox_memory: 1g
sandbox_memory_swap: 1g
sandbox_cpus: 1
sandbox_pids_limit: 128
sandbox_nofile_soft: 1024
sandbox_nofile_hard: 2048

searxng_image: >-
  ghcr.io/searxng/searxng:2026.8.20-8d3dd0cd4@sha256:9fd6172d7dcec4920273995ccd33338e4cda3093a468261a479f46a2d212723b
searxng_bind_address: 127.0.0.1
searxng_port: 8888

restic_enabled: false
```

Apply protected permissions:

```sh
sudo chown -R root:root /root/openclaw-inventory
sudo find /root/openclaw-inventory -type d -exec chmod 0700 {} \;
sudo find /root/openclaw-inventory -type f -exec chmod 0600 {} \;
```

## 7. Create the encrypted secrets file

Generate two distinct random values. They will be printed once; paste them into
the SOPS editor and do not save them in shell variables or plaintext files:

```sh
openssl rand -hex 32
openssl rand -hex 32
```

Get the public recipient again:

```sh
sudo age-keygen -y /root/.config/sops/age/keys.txt
```

Then create the encrypted file. Replace `REPLACE_AGE_RECIPIENT` with the public
`age1...` value, not the private identity:

```sh
sudo env \
  SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt \
  EDITOR=nano \
  sops --age REPLACE_AGE_RECIPIENT \
  /root/openclaw-inventory/group_vars/secrets.sops.yml
```

Enter this YAML using the two generated values:

```yaml
gateway_token: "REPLACE_WITH_FIRST_RANDOM_VALUE"
searxng_secret_key: "REPLACE_WITH_SECOND_RANDOM_VALUE"
```

Save and exit. Confirm that SOPS metadata and encrypted values exist without
printing decrypted content:

```sh
sudo grep -E '^(gateway_token|searxng_secret_key|sops):' \
  /root/openclaw-inventory/group_vars/secrets.sops.yml
sudo env SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt \
  sops --decrypt /root/openclaw-inventory/group_vars/secrets.sops.yml >/dev/null
```

## 8. Download and verify the v1.1.0 bootstrap

Use a clean directory on the Pi:

```sh
mkdir -p "$HOME/openclaw-bootstrap"
cd "$HOME/openclaw-bootstrap"
RELEASE=v1.1.0
BASE_URL="https://github.com/gromer/openclaw-pi/releases/download/${RELEASE}"

curl -fsSLO "${BASE_URL}/bootstrap.sh"
curl -fsSLO "${BASE_URL}/bootstrap.sh.sha256"
sha256sum --check bootstrap.sh.sha256
less bootstrap.sh
```

Do not use `curl | sudo sh`. The bootstrap will independently download and
verify the full Ansible release archive.

## 9. Validate and provision

First perform dependency-light release and Ansible syntax validation:

```sh
sudo OPENCLAW_PI_RELEASE=v1.1.0 sh bootstrap.sh --validate-only
```

Ansible check mode can be useful, but on a completely fresh machine some later
checks may fail because check mode intentionally does not create prerequisite
users, packages, or services. Treat it as a best-effort preview:

```sh
sudo OPENCLAW_PI_RELEASE=v1.1.0 \
  OPENCLAW_PI_INVENTORY=/root/openclaw-inventory/hosts.yml \
  sh bootstrap.sh --dry-run
```

Provision the Pi:

```sh
sudo OPENCLAW_PI_RELEASE=v1.1.0 \
  OPENCLAW_PI_INVENTORY=/root/openclaw-inventory/hosts.yml \
  sh bootstrap.sh
```

The inference reachability task deliberately stops provisioning if the Pi cannot
reach Ollama or receive HTTP 200 from `/api/tags`.

## 10. Verify SSH before closing the original session

Provisioning disables password login, denies root login, restricts SSH to
`piadmin`, and enables UFW after permitting SSH. From a **new workstation
terminal**, connect using the new account:

```sh
ssh -i "$HOME/.ssh/id_ed25519" piadmin@REPLACE_PI_IP
```

Do not close the original console or SSH session until this succeeds. If it
fails, use the existing session or local console to inspect:

```sh
sudo sshd -t
sudo journalctl -u ssh --no-pager -n 100
sudo ufw status verbose
sudo ls -ld /home/piadmin/.ssh
sudo ls -l /home/piadmin/.ssh/authorized_keys
```

## 11. Verify services and open the dashboard

From the new `piadmin` session:

```sh
sudo systemctl --no-pager --full status docker openclaw
sudo docker compose -f /opt/openclaw-compose/searxng/compose.yml ps
curl --fail http://127.0.0.1:18789/health
curl --fail http://127.0.0.1:8888/healthz
sudo journalctl -u openclaw --no-pager -n 100
```

On the workstation, create an SSH tunnel and leave it running:

```sh
ssh -N -L 18789:127.0.0.1:18789 piadmin@REPLACE_PI_IP
```

Open `http://127.0.0.1:18789` in the workstation browser. Retrieve the gateway
token by opening the encrypted file through SOPS on the Pi:

```sh
sudo env \
  SOPS_AGE_KEY_FILE=/root/.config/sops/age/keys.txt \
  sops /root/openclaw-inventory/group_vars/secrets.sops.yml
```

Copy only the `gateway_token` value into the dashboard, then exit the editor
without changing the file.

## 12. After the first successful login

- Store the production inventory and encrypted SOPS file in protected backup
  storage; keep the age identity backed up separately.
- Configure Restic before relying on the Pi for irreplaceable workspace or
  session state.
- Test an OpenClaw request and confirm it uses the expected Ollama model.
- Confirm a sandbox container has network mode `none`, a read-only root, and no
  Docker socket mount.
- Record the installed release with `readlink -f /opt/openclaw-pi/current`.
- Schedule a recovery drill using the disaster-recovery runbook.

For operations and recovery, continue with the [main README](../README.md),
[bootstrap runbook](bootstrap.md), and
[disaster-recovery guide](disaster-recovery.md).

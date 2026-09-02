# OpenClaw Raspberry Pi 5 gateway

Reproducible Ansible provisioning for a 64-bit Raspberry Pi OS Raspberry Pi 5.
OpenClaw runs as an unprivileged host systemd service, Docker runs isolated tool
sandboxes, Compose runs loopback-only SearXNG, and inference remains on an M4 Pro
Mac over the LAN.

## Quick install

On an updated Raspberry Pi 5 running 64-bit Raspberry Pi OS, enable SSH and make
sure the Pi can reach an Ollama server over the LAN. Then run:

```sh
curl -fsSL https://github.com/gromer/openclaw-pi/releases/latest/download/install.sh | sudo sh
```

The guided installer selects the latest published release, pins it to that
release tag, verifies the bootstrap and Ansible bundle checksums, reuses an
existing SSH public key, and prompts for the Ollama URL and exact model. It
generates the age identity and encrypted service secrets locally. Back up the
age identity securely as soon as installation finishes.

This convenience command executes network-delivered code as root before you can
inspect or independently verify the installer. For production, use the
[checksum-verified installation](#initial-setup) or the detailed
[bootstrap runbook](docs/bootstrap.md).

## Architecture and trust boundaries

The gateway and SearXNG listen on loopback; administer them through SSH port
forwarding. OpenClaw connects only to the inventory-selected Mac endpoint. Tool
sandboxes use network `none`, read-only roots, tmpfs scratch space, no devices or
host namespaces, all capabilities dropped, and CPU/memory/PID/file-descriptor
limits. Workspace access defaults to `none`.

**Critical limitation:** OpenClaw's verified Docker backend invokes the Docker
CLI and therefore the `openclaw` account is in the Docker group. Docker daemon
authority is effectively root authority on the Pi. The sandbox containers never
receive the socket, but a compromised gateway process could control Docker. This
is the closest supported host-gateway design; use a separate sandbox host/backend
if that trust is unacceptable. SearXNG is intentionally unavailable inside
network-disabled tool sandboxes; host-integrated tools can reach it.

Git-managed configuration is reconstructible. `/var/lib/openclaw` contains
private mutable workspace, SQLite state, sessions, and credentials and is the
default Restic backup selection. Never commit that tree.

## Repository map

- [`inventories/example`](inventories/example/) contains safe illustrative host
  and variable examples. Copy it to the ignored `inventories/production/` tree
  and replace every example value before use.
- [`playbooks/site.yml`](playbooks/site.yml) provisions the gateway;
  [`playbooks/verify.yml`](playbooks/verify.yml) runs post-provision checks.
- [`roles/`](roles/) owns the base system, users, firewall, Docker, OpenClaw,
  sandbox, SearXNG, Restic, and verification configuration.
- [`compose/searxng`](compose/searxng/) and [`openclaw/`](openclaw/) contain
  intentional Git-managed service and workspace files; mutable runtime data is
  kept outside the repository.
- [`docs/`](docs/) contains the [bootstrap runbook](docs/bootstrap.md),
  [fresh-Pi/Ollama guide](docs/getting-started-ollama.md),
  [validation scope](docs/validation.md), and
  [disaster-recovery runbook](docs/disaster-recovery.md).

## Supported platform and verified upstream contract

The target is current 64-bit Raspberry Pi OS (Debian-family) on Pi 5. OpenClaw
2026.7.1 is the committed example pin. Node 24 is selected because current
OpenClaw supports Node 24.15+ (Node 26 is recommended upstream). Review and update
pins deliberately before production.

Authoritative references consulted August 26, 2026:

- [OpenClaw install and requirements](https://docs.openclaw.ai/install),
  [Node requirements](https://docs.openclaw.ai/install/node), and
  [releases](https://github.com/openclaw/openclaw/releases)
- [configuration reference](https://docs.openclaw.ai/gateway/configuration-reference),
  [custom providers](https://docs.openclaw.ai/gateway/config-tools),
  [Ollama](https://docs.openclaw.ai/providers/ollama), and
  [local/MLX endpoints](https://docs.openclaw.ai/gateway/local-models), and
  [OpenRouter](https://docs.openclaw.ai/providers/openrouter)
- [workspace contract](https://docs.openclaw.ai/agent-workspace) and
  [Docker sandboxing](https://docs.openclaw.ai/gateway/sandboxing)
- [Docker Engine on Debian](https://docs.docker.com/engine/install/debian/)
- [SearXNG container installation](https://docs.searxng.org/admin/installation-docker.html)
  and [settings](https://docs.searxng.org/admin/settings/index.html)
- [SOPS reference](https://getsops.io/docs/reference/),
  [age](https://age-encryption.org/), and
  [Restic documentation](https://restic.readthedocs.io/en/stable/)

OpenClaw configuration is JSON (valid JSON5), at `/etc/openclaw/openclaw.json`.
The MLX path uses the documented `openai-completions` adapter and `/v1`; Ollama
uses its native `ollama` adapter. The exact authored provider base URL is the LAN
origin trusted by OpenClaw's guarded fetch path.

## Initial setup

For an end-to-end first installation using an existing Ollama server, follow
[Getting started with a fresh Pi and Ollama](docs/getting-started-ollama.md).

For a fresh Pi that already has SSH access and can reach Ollama, the recommended
installer flow downloads the latest installer and its checksum as separate
release assets before running it:

These URLs require a release containing `install.sh`; merging this feature alone
does not add assets to an older release.
Releases `v1.0.0` through `v1.2.0` predate immutable-release hardening and are
superseded; use `v1.2.3` or a newer published release for production
installations.

```sh
mkdir -p "$HOME/openclaw-install" && cd "$HOME/openclaw-install"
curl --fail --silent --show-error --location --remote-name \
  https://github.com/gromer/openclaw-pi/releases/latest/download/install.sh
curl --fail --silent --show-error --location --remote-name \
  https://github.com/gromer/openclaw-pi/releases/latest/download/install.sh.sha256
sha256sum --check install.sh.sha256
less install.sh
sudo sh install.sh
```

The installer asks for the Ollama URL and exact model, reuses an existing SSH
public key, generates age and application secrets locally, builds a root-only
inventory, resolves `latest` to a published release tag, and runs the existing
checksum-verifying bootstrap. This installer is the **convenience/local SOPS
mode**: the private age identity is generated and stored on the Pi at
`/root/.config/sops/age/keys.txt` (root-only). Back up that identity
immediately to encrypted offline custody. Restic remains disabled until a real
repository is deliberately configured.

Install Raspberry Pi OS 64-bit, enable SSH, create an initial administrative
account, apply OS updates, and reserve a DHCP address. On the controller:

NetworkManager changes are opt-in with `pi_manage_network: true` because applying
an address remotely can terminate SSH. Keep it false for DHCP reservations; for
static configuration, confirm the connection name locally with `nmcli connection
show` and use console access for the first apply.

```sh
mkdir -p inventories/production/group_vars
cp inventories/example/hosts.yml inventories/production/hosts.yml
cp inventories/example/group_vars/all.yml inventories/production/group_vars/all.yml
# edit production hosts.yml and group_vars/all.yml
age-keygen -o "$HOME/.config/sops/age/keys.txt"
# copy only the printed public recipient into .sops.yaml
make secrets-init
```

This path is the **controller SOPS mode**: keep the private age identity off
the Pi, commit only encrypted `*.sops.yml`, and copy only ciphertext to the Pi.
If Ansible must decrypt on the Pi, stage the key there as a root-only temporary
file for the run and remove it afterward.

Inside the encrypted file create:

```yaml
gateway_token: "a randomly generated value of at least 32 characters"
searxng_secret_key: "a distinct random value of at least 32 characters"
inference_api_key: "optional token required by the MLX endpoint"
openrouter_api_key: "optional OpenRouter API key"
restic_password: "a strong randomly generated Restic password"
restic_environment: "optional backend variables, one NAME=value per line"
```

`.sops.yaml` deliberately contains an invalid recipient marker; no fake
ciphertext is committed. Back up the age identity encrypted and offline in at
least two controlled locations. The public recipient is safe to commit; the
identity is not. Verify each backup by confirming
`age-keygen -y <backup-copy>` matches the recipient in `.sops.yaml`. Rotate the
recipient and re-encrypt `secrets.sops.yml` if custody changes or on a scheduled
cadence. If any identity copy is exposed, treat all encrypted secrets as
compromised: rotate the age identity, re-encrypt SOPS files, regenerate service
secrets, and reprovision.

## Versioned remote bootstrap

Release assets are generated by GitHub Actions. The bootstrap script installs
only the initial controller dependencies, checks that the machine is a 64-bit
Raspberry Pi 5 running Raspberry Pi OS, downloads and verifies the complete
Ansible bundle for a published release tag, installs it under
`/opt/openclaw-pi/releases`, and runs the selected validation or provisioning
target. Git and repository access are not required on the Pi.

Before downloading it, securely stage the ignored production inventory on the
Pi. If Ansible will decrypt SOPS secrets on the Pi, also install SOPS and stage
the age identity somewhere readable only by root. For example:

```sh
sudo install -d -m 0700 /root/openclaw-inventory/group_vars
sudo install -m 0600 hosts.yml /root/openclaw-inventory/hosts.yml
sudo install -m 0600 all.yml /root/openclaw-inventory/group_vars/all.yml
sudo install -m 0600 secrets.sops.yml \
  /root/openclaw-inventory/group_vars/secrets.sops.yml
sudo install -d -m 0700 /root/.config/sops/age
sudo install -m 0600 keys.txt /root/.config/sops/age/keys.txt
```

Never commit identities or decrypted files, include them in release assets, or
print them in command traces/logs.

Set the published version, then download the script and checksum as separate
files. Do not pipe the network response directly into a root shell:

```sh
RELEASE=vX.Y.Z
BASE_URL="https://github.com/gromer/openclaw-pi/releases/download/${RELEASE}"
curl -fsSLO "${BASE_URL}/bootstrap.sh"
curl -fsSLO "${BASE_URL}/bootstrap.sh.sha256"
sha256sum --check bootstrap.sh.sha256
less bootstrap.sh
sudo OPENCLAW_PI_RELEASE="$RELEASE" \
  OPENCLAW_PI_INVENTORY=/root/openclaw-inventory/hosts.yml sh bootstrap.sh
```

`OPENCLAW_PI_RELEASE` is required and mutable names such as `main`, `master`,
`latest`, and `HEAD` are rejected. `OPENCLAW_PI_REPOSITORY` defaults to
`gromer/openclaw-pi`; `OPENCLAW_PI_ASSET_BASE_URL` can select a trusted HTTPS
release mirror. `OPENCLAW_PI_DEST` optionally changes the install root from
`/opt/openclaw-pi`.

Each GitHub Release contains the installer and bootstrap files, the complete versioned
`openclaw-pi-<tag>.tar.gz` Ansible bundle, SHA-256 files, and a provenance
manifest recording the Git commit. The bootstrap verifies the archive before
extracting it, rejects path traversal and links, never overwrites an installed
release with different content, and atomically changes the `current` symlink.
The previous release remains available for rollback.

Use validation-only mode before provisioning, or Ansible check mode to preview
changes:

```sh
sudo OPENCLAW_PI_RELEASE="$RELEASE" sh bootstrap.sh --validate-only

sudo OPENCLAW_PI_RELEASE="$RELEASE" \
  OPENCLAW_PI_INVENTORY=/root/openclaw-inventory/hosts.yml \
  sh bootstrap.sh --dry-run
```

Public release assets need no GitHub credentials even if the operator has no Git
checkout. Private-release downloads require an authenticated distribution step;
mirror all release assets to a controlled HTTPS origin and set
`OPENCLAW_PI_ASSET_BASE_URL`. Never put tokens, SOPS values, Restic passwords, or
age identities in command-line flags or bootstrap environment values. See
[the complete bootstrap guide](docs/bootstrap.md) for argument behavior,
troubleshooting, and release verification.

## Inference on the Mac

For Ollama, install it from its official distribution, pull the exact inventory
model, and configure Ollama to listen on the Mac's LAN interface. Restrict port
11434 in the macOS firewall to the Pi address. Set `inference_backend: ollama`,
`inference_base_url: http://MAC:11434`, and the exact model ID. Confirm from the
Pi with `curl http://MAC:11434/api/tags`.

For MLX, run a maintained OpenAI-compatible server whose documented endpoint
implements `/v1/models` and `/v1/chat/completions`. Bind it to the LAN address,
require a token where supported, and restrict the port to the Pi. Set
`inference_backend: mlx_openai`, a base ending in `/v1`, its exact advertised
model ID, and `inference_api_key` in SOPS. Never expose either service publicly.
OpenRouter is registered alongside the selected local inference backend. Add
`openrouter_api_key` to the encrypted SOPS file to use
`openrouter/auto-beta`; the explicit catalog and allowlist entries
keep OpenRouter Auto (Beta) visible in OpenClaw's chat and `/model` pickers.
Current role wiring keeps provider secrets in a root-owned systemd
`EnvironmentFile`; OpenClaw SecretRefs/systemd credentials were evaluated but are
not configured here because upstream provider auth still expects environment
variables.

## Operations

```sh
make deps
make check
make preflight
make diff
make provision
make verify
make secrets-check
make backup-check
ssh -N -L 18789:127.0.0.1:18789 piadmin@PI
```

Run `make help` for the complete interface, including `make syntax`, `make
lint`, `make backup`, and the guarded `make restore` target. The
[validation guide](docs/validation.md) explains which checks are
credential-free and which require the actual Pi, inference host, or Restic
repository.

Open `http://127.0.0.1:18789` after the tunnel is established. Upgrade by changing
reviewed pins, running `make check`, then `make diff` and `make provision`.
Hardware verification checks service health and inspects any existing sandbox
containers for obvious isolation regressions. Provisioning installs Docker
Engine, the Docker CLI, Buildx, and Compose from Docker's official Debian
repository, enables the daemon, and verifies daemon and plugin access as the
unprivileged `openclaw` service account before building the sandbox image.

Backups run with systemd. Initialize/backup with `make backup`; check the backend
using `make backup-check` in a protected environment. Retention uses daily,
weekly, and monthly policy variables and prunes only after a successful backup.
Repository checks sample data weekly. Investigate timer failures and verify
freshness within `restic_max_backup_age_hours`.

Restore is intentionally controller-side and refuses `latest` or a non-empty
target without confirmation:

```sh
restic snapshots
make restore SNAPSHOT=EXPLICIT_ID TARGET=/safe/staging/path
# after inspection only:
make restore SNAPSHOT=EXPLICIT_ID TARGET=/safe/staging/path CONFIRM=--confirm-overwrite
```

Stop OpenClaw before replacing live SQLite/state, restore to staging, validate
ownership and content, then use `rsync` deliberately. Git-managed `/etc` files
should be reprovisioned, not restored.

## Firewall, troubleshooting, and security

UFW permits SSH before default-deny is enabled. Gateway and SearXNG LAN exposure
are rejected by inventory validation. Verify inference DNS/address, Mac firewall,
and `/api/tags` or `/v1/models` if provisioning stops before OpenClaw restart.
Use `journalctl -u openclaw`, `docker compose -f
/opt/openclaw-compose/searxng/compose.yml logs`, `openclaw config validate`, and
`openclaw sandbox explain` for diagnosis. Never disable host-key checking or
temporarily publish ports to troubleshoot.

The provisioning supply chain is verified at each boundary: NodeSource and
Docker repository keys are checked against their documented fingerprints, and
the OpenClaw tarball is downloaded with lifecycle scripts disabled, hashed, and
compared with the inventory's npm `dist.integrity` value before installation as
the unprivileged service user. The sandbox Dockerfile pins the Debian
bookworm-slim multi-architecture index by digest. Review these pins deliberately
when upgrading: obtain the new NodeSource/Docker key fingerprints from their
official documentation, obtain OpenClaw's value with `npm view
openclaw@VERSION dist.integrity`, and obtain a new base digest with `docker
buildx imagetools inspect debian:bookworm-slim`. Update the corresponding
defaults/inventory value and run `make check` before provisioning.

See [docs/disaster-recovery.md](docs/disaster-recovery.md) for recovery and
[docs/validation.md](docs/validation.md) for test scope.

Contribution workflow and repository invariants are documented in
[`AGENTS.md`](AGENTS.md) and [`CONTRIBUTING.md`](CONTRIBUTING.md). See
[`SECURITY.md`](SECURITY.md) for vulnerability reporting and security
boundaries.

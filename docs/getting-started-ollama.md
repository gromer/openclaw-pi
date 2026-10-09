# Fresh Raspberry Pi and Ollama setup

This guide prepares a new Raspberry Pi 5 to run the production-matching
OpenClaw user service. It does not copy or modify the production card. For the
full architecture comparison, credential migration steps, and recovery
boundaries, see [production reconciliation](production-reconciliation.md).

## Operating-system and SSH baseline

Install current 64-bit Raspberry Pi OS for Pi 5, Debian 13/Trixie. Enable SSH
on port 2222 in Raspberry Pi Imager or at the local console. Create the intended
administrator/service account (the example is `gromer`) and add its
workstation public key. Confirm the new host's SSH host-key fingerprint at the
console before accepting it from the workstation.

Prefer DHCP plus a router reservation. The example keeps
`pi_manage_network: false`; changing NetworkManager remotely can terminate the
SSH session. Do not run the production and test cards simultaneously with the
same hostname/IP. When swapping cards, compare the console fingerprint and
remove only the old known-host entry after verification.

## Prepare credentials manually

The gateway and authenticated Ollama tokens are managed in Proton Pass
Automation. Before provisioning, create
`/home/gromer/.config/openclaw/secrets` owned by `gromer:gromer` with mode
0700. Use a local text editor to create `gateway-token.json` with the existing
gateway token and `ollama-caddy-token.json` with the existing Caddy token in
these JSON shapes:

```json
{"GATEWAY_AUTH_TOKEN":"<paste in editor>"}
{"OLLAMA_CADDY_TOKEN":"<paste in editor>"}
```

Set both file owners to `gromer:gromer` and modes to 0600; keep one hard link
per file. Do not generate a replacement token or place values in shell
commands, SOPS, Ansible output, logs, or Git. The installer and Ansible check
file metadata only.

Firecrawl remains optional at base install. If the migration is being prepared
on the test card, create `firecrawl.env` in the same protected directory with a
local editor and this systemd EnvironmentFile line:

```text
FIRECRAWL_API_KEY=<paste in editor>
```

Keep it owned by `gromer:gromer`, mode 0600. Do not enable
`firecrawl_secret_enabled` until this file is present.

## Provision

Use the checksum-verified installer/bootstrap flow in [bootstrap.md](bootstrap.md).
For a controller-side checkout, copy the example inventory into the ignored
`inventories/production/` directory and set the SSH target, hostname, Control UI
origins, permitted CIDRs, Ollama endpoint, and exact model. Keep
`secrets_file` protected and use it only for non-gateway service values such as
SearXNG and an optional authenticated inference endpoint.

The pinned release installs Node.js 24 and OpenClaw 2026.9.6 with npm registry
integrity verification. Ansible installs Docker/Compose and supporting host
services, creates the user-service directories, enables lingering for
`gromer`, installs `openclaw-gateway.service`, and starts it after confirming
the gateway token file's owner and mode. Configuration is seeded only when
`~/.openclaw/openclaw.json` is absent; subsequent applies leave the whole
application config alone.

Run the repository checks before applying:

```sh
make check
make diff
make provision
make verify
```

The first boot test must verify `loginctl show-user gromer -p Linger`,
`systemctl --user status openclaw-gateway.service`,
`openclaw config validate`, Gateway health, Docker access, firewall behavior,
and persistence after a controlled restart. Hardware and boot checks have not
been exercised in CI.

## Restore beyond the base gateway

A healthy base Gateway does not restore production agents, channels, device
pairings, plugin state, external workspaces, or SQLite data. Full recovery
requires a verified encrypted backup/snapshot and manually restored credentials
from Proton Pass. Restic is disabled by default; configure and test it before
relying on it. Restore to a staging directory on the separate card, check file
ownership and SQLite integrity, then deliberately install the selected state.
Never copy runtime state into Git.

Do not shut down or alter the production Pi as part of this guide. A future
physical card swap is a separate operator action and should preserve the
original card untouched for rollback.

# Production architecture, credentials, and microSD recovery

This runbook describes the repository target and the preparation state checked
on 2026-10-08. It does not authorize a production apply or service restart.

## Observed production and repository drift

Read-only SSH to `openclaw:2222` on 2026-10-08 verified Debian 13 ARM64,
OpenClaw 2026.9.6, user `gromer` (UID 1000), and this active, enabled user unit:

```text
~/.config/systemd/user/openclaw-gateway.service
openclaw-gateway.service: Restart=always, RestartSec=5s
ExecStart: /usr/bin/node .../.npm-global/lib/node_modules/openclaw/dist/index.js gateway --port 18789
```

`loginctl` reported lingering enabled. `openclaw config file` reported
`/home/gromer/.openclaw/openclaw.json`. The home and `.openclaw` directories
were mode 0700 and owned by `gromer`; `.npm-global` was mode 0755 and owned by
`gromer`. The production service unit itself was mode 0600 and owned by
`gromer`. The package directory is not a checkout of this repository.
The active default route used `eth0`; NetworkManager reported `wlan0`
unavailable. The system-level legacy `openclaw.service` was not found. No
matching user or system Restic/OpenClaw backup timers or units were listed.
Those checks do not establish the status of external backups or a Restic
repository. Firewall rules and detailed DHCP/DNS configuration were not read.

The prior role declared a separate `openclaw` system account, a root-owned
`/etc/systemd/system/openclaw.service`, `/etc/openclaw/openclaw.json`,
`/var/lib/openclaw`, and a root-managed environment file. That design also
rendered a complete agent/model configuration on every apply. It did not match
the working user service and could overwrite manually managed agents,
integrations, and runtime settings.

The role now targets the production user-service model and only seeds
`openclaw.json` when it does not exist. Existing application configuration is
left in place. `~/.openclaw` is persistent mutable state, not a declarative
copy of the repository. Agent workspaces, channels, plugin state, device
identity, SQLite data, and credentials must be recovered or configured
separately for a full environment restore.

The current production config, its credential values, conversations, session
state, and process environment were not read. No files or services on the Pi
were changed. Current full-state backup availability and restore readiness
remain unverified.

## Base installation on a separate microSD card

Base installation means a working OpenClaw 2026.9.6 gateway with the intended
user service, persistent user manager, protected token reference, and network
policy. It does not restore the production agent fleet or integrations.

1. On a separate card, install 64-bit Raspberry Pi OS for Raspberry Pi 5,
   Debian 13/Trixie baseline. Enable SSH on port 2222, create the `gromer`
   account, install its workstation public key, and use DHCP with a router
   reservation where possible. Keep `pi_manage_network: false` unless network
   changes are being applied from a local console.
2. Confirm the new host's SSH host-key fingerprint at its console before
   accepting it. The production card and test card may use the same hostname or
   IP at different times; remove only the stale `openclaw` known-host entry
   after independently verifying the new fingerprint. Never disable host-key
   checking to work around a mismatch.
3. Install the gateway and Ollama token files manually from Proton Pass
   Automation before running the playbook. Keep existing values when
   reproducing production. Create `/home/gromer/.config/openclaw/secrets` with
   mode 0700 and owner `gromer`, then use a local editor to create
   `gateway-token.json` as `{"GATEWAY_AUTH_TOKEN":"<paste in editor>"}` and
   `ollama-caddy-token.json` as
   `{"OLLAMA_CADDY_TOKEN":"<paste in editor>"}`. Set owner `gromer:gromer`,
   mode 0600, and one hard link per file. Do not put values in shell commands,
   terminal transcripts, Ansible inventory, SOPS, or Git.
4. Use the checksum-verified release/bootstrap process in
   [bootstrap.md](bootstrap.md). Review the example inventory and set the
   confirmed Ollama endpoint/model and the intended host name/origins. The
   target has Node.js 24 and the OpenClaw 2026.9.6 npm package pinned by registry
   integrity. Docker Engine, Compose, firewall, SearXNG, and sandbox roles are
   provisioned by the existing playbook.
5. Ansible enables lingering for `gromer`, installs and enables
   `~/.config/systemd/user/openclaw-gateway.service` under
   `default.target`, and uses `Restart=always` with a five-second delay. The
   service runs as `gromer`; it uses the normal `~/.openclaw` state/config
   paths. Network and Docker are managed by system services. The user unit has
   no cross-manager `Requires=` ordering; the playbook checks Docker access
   and Gateway health after startup.
6. Run `make check`, `make diff`, `make provision`, and `make verify`. Confirm
   `loginctl show-user gromer -p Linger`, the user unit's active/enabled state,
   `openclaw config validate`, Gateway health, Docker access, and the sandbox
   checks. A separate-card test is required for ARM64 packages, systemd user
   manager behavior, firewall reachability, and boot persistence.

The guided installer skips its unauthenticated `/api/tags` check for
`https://ollama.gromer.dev`; that Caddy route requires the protected file-backed
token. Confirm the selected model in inventory and validate provider
connectivity after startup without printing credentials.

The installer expects an OS user named by `admin_user` and requires the gateway
token file to exist with owner/mode checks before provisioning. It does not
create or rotate that credential. The example uses `gromer` for both
administration and the gateway, matching production. Membership in `sudo` and
the Docker group gives the gateway process host-administration-equivalent
authority; the user-service model is faithful to production but is not a
separate privilege boundary.

## Gateway token migration (issue #8)

OpenClaw 2026.9.6's installed JSON schema accepts a file SecretRef at
`gateway.auth.token`. The JSON-mode provider points at
`/home/gromer/.config/openclaw/secrets/gateway-token.json` and selects the
`/GATEWAY_AUTH_TOKEN` JSON pointer. The file must be a JSON object. Keep the
current token by manually provisioning the same Proton Pass value; do not
rotate it for this storage change.

The file provider requires a private regular file, rejects symlinks and
hardlinks, and resolves JSON-mode IDs as JSON pointers. A SecretRef on the
active Gateway auth surface must resolve; OpenClaw reports that surface state
and fails closed if resolution fails. See the [SecretRef contract](https://docs.openclaw.ai/gateway/secrets/secretref-contract)
and [runtime behavior](https://docs.openclaw.ai/gateway/secrets/runtime-model).

After a future separately authorized maintenance window, first make a
restricted owner-only backup of `~/.openclaw/openclaw.json` without printing
its contents. Provision and metadata-check the token file, then use the
installed supported CLI builders:

```sh
openclaw config set secrets.providers.gateway_token_file \
  --provider-source file \
  --provider-path /home/gromer/.config/openclaw/secrets/gateway-token.json \
  --provider-mode json
openclaw config set gateway.auth.token \
  --ref-source file --ref-provider gateway_token_file \
  --ref-id /GATEWAY_AUTH_TOKEN
openclaw config validate
openclaw secrets reload
openclaw secrets audit --check
```

The provider must resolve before the service restarts. Then restart
`openclaw-gateway.service` with `systemctl --user restart`; verify active state,
Gateway health, and a read-only client connection. The new runtime snapshot is
used after `secrets reload`; restart is required to make a failed startup or
service-level environment change recover cleanly. Existing clients keep the
same token, though active WebSocket clients may disconnect briefly and
reconnect. Assess other Gateway API consumers and scheduled jobs in the
maintenance plan. Telegram and agents are not reconfigured by this operation.

If SecretRef validation or startup fails, restore the restricted config backup
and restart the same user unit. Keep the file available until rollback is
complete. Do not copy the token value into a command, log, issue, or Git.

The metadata-only schema check did not exercise a live auth transition. The
future change still requires the targeted audit, an authorized restart, a
read-only client reconnection check, and an audit showing no plaintext token.

## Firecrawl key migration (issue #9)

The installed Firecrawl plugin is version 2026.9.5. Its installed manifest
documents `FIRECRAWL_API_KEY` as the fallback environment variable, and the
installed OpenClaw schema accepts SecretRef objects for the plugin's
`webSearch.apiKey` field. Use an environment-backed SecretRef with an explicit
single-variable allowlist. This avoids the unsupported file SecretRef at that
plugin field and preserves the configured Firecrawl search provider.

Create `/home/gromer/.config/openclaw/secrets/firecrawl.env` manually with a
local editor and this systemd EnvironmentFile syntax (no `export` prefix):

```text
FIRECRAWL_API_KEY=<paste in editor>
```

The file must be regular, non-symlinked, owned by `gromer:gromer`, and mode
0600; its parent directory is 0700. systemd parses `NAME=value` lines itself;
it does not run a shell or expand shell substitutions ([systemd.exec](https://manpages.debian.org/unstable/systemd/systemd.exec.5.en.html)). The value is added to
the Gateway unit's process environment and inherited by its child processes;
keep this file limited to the single allowed Firecrawl variable. Do not use
command arguments or shell history to enter the key.

For a future authorized apply, set `firecrawl_secret_enabled: true` in the
protected provisioning inventory. The role installs a user-service drop-in at
`~/.config/systemd/user/openclaw-gateway.service.d/firecrawl-env.conf` with:

```ini
[Service]
EnvironmentFile=/home/gromer/.config/openclaw/secrets/firecrawl.env
```

Then add the environment SecretRef while preserving the rest of the plugin
configuration:

```sh
openclaw config set secrets.providers.firecrawl_env \
  --strict-json '{"source":"env","allowlist":["FIRECRAWL_API_KEY"]}'
openclaw config set plugins.entries.firecrawl.config.webSearch.apiKey \
  --ref-source env --ref-provider firecrawl_env --ref-id FIRECRAWL_API_KEY
openclaw config validate
openclaw secrets reload
openclaw secrets audit --check
```

Restart the user service so systemd reads the new EnvironmentFile. Confirm the
plugin remains loaded and perform one targeted Firecrawl validation using the
existing integration only after that live query is separately authorized. The
repository does not add a Firecrawl test query or change other plugin fields.
If validation fails, restore the restricted config backup, remove the drop-in
through the reviewed provisioning change, reload the user manager, and restart
the service. Keep the key in Proton Pass; do not back it up in SOPS or Git.

## Full environment recovery

Full recovery (level B) needs more than a Gateway service and config. Preserve
and restore, from an encrypted and access-controlled backup or the owning
component repositories:

- `/home/gromer/.openclaw`, including the manually managed config, agent
  workspaces under that tree, device identity, plugin state, and SQLite data;
- external agent workspaces/repositories such as `/home/gromer/openclaw-homelab-ops`
  and any source repositories needed to recreate them;
- channel/provider credentials, plugin install sources/versions, and required
  files under `.config/openclaw/secrets`, provisioned separately from Proton
  Pass; and
- the matching user, UID ownership, home permissions, network address/DNS,
  SSH trust, Node/OpenClaw version, Docker images, and sandbox configuration.

Never put conversations, SQLite databases, device identities, authentication
profiles, private keys, or host secrets in Git. The current production Restic
repository and recovery point were not inspected. In this repository Restic
is opt-in (`restic_enabled: false` by default). Before relying on it for level B,
configure a protected repository, confirm the backup includes the actual
mutable state you need, and rehearse a restore to a staging directory on the
separate card. Credential files should be reprovisioned manually, not copied
from a state snapshot.

The separate-card fallback is: shut down only when a future operator chooses
to perform the hardware test, swap cards, validate the test installation, and
power down before reinserting the original card. No current-card image or
clone is required. Do not boot both cards with the same IP/hostname at once.

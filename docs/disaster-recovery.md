# Disaster recovery

Recovery has two distinct outcomes. Level A restores a working Gateway and its
intended user-service architecture. Level B restores the agents, integrations,
and durable application state. A level A install does not imply level B
readiness. See [production reconciliation](production-reconciliation.md) for
the current microSD procedure and manual credential setup.

## Level A: base gateway

1. Use a separate Raspberry Pi 5 microSD card with 64-bit Raspberry Pi OS,
   Debian 13/Trixie. Do not clone the active card. Enable SSH, create `gromer`,
   install its public key, and confirm the new SSH host key at the console.
2. Restore the protected, non-secret inventory from Git or a verified archive.
   Recheck hostname, DHCP reservation, Control UI origins, firewall CIDRs, and
   Ollama endpoint for the test card.
3. Manually provision the existing gateway and Ollama token files from Proton
   Pass under `/home/gromer/.config/openclaw/secrets/`, mode 0600, owner
   `gromer:gromer`; the parent must be mode 0700. Keep credentials out of
   inventory and SOPS.
4. Follow [bootstrap.md](bootstrap.md), then run `make check`, `make diff`,
   `make provision`, and `make verify`. Confirm the enabled user service,
   lingering, config validation, Gateway health, firewall behavior, Docker
   access, and sandbox isolation.
5. Reboot only the test card during a planned hardware test. Confirm the
   service starts without an interactive login. Keep the original card
   untouched so it remains the rollback path.

## Level B: full environment

Before depending on recovery, configure Restic with protected repository
credentials and make a successful backup. Verify the selected snapshot covers
`/home/gromer/.openclaw`, including agent workspaces under that tree, SQLite
databases, device identity, and plugin state. Also identify separately stored
agent repositories/workspaces and manually managed credentials. Restic is
disabled by default; no production snapshot or restore was verified in the
2026-10-08 investigation.

1. Prepare the level A test card and verify the gateway before restoring state.
2. In a protected environment, list snapshots using the configured Restic
   repository and select a known-good snapshot ID. Never assume the newest
   snapshot is valid.
3. Restore the selected snapshot to an empty staging directory. Inspect paths,
   dates, ownership, and SQLite integrity without exposing conversations or
   secret values. Do not restore credentials from the snapshot; retrieve and
   provision them manually from Proton Pass.
4. Stop the test Gateway using its user manager, preserve the newly generated
   state, and copy the selected staged state into
   `/home/gromer/.openclaw`. Restore ownership to `gromer`, mode 0700 for the
   state root, and more restrictive modes where required.
5. Reinstall or restore external agent repositories from their owning Git
   repositories, then apply documented channel, plugin, model, and SecretRef
   configuration while preserving the selected state.
6. Start the user service and verify Gateway health, client authentication,
   device pairing state, channel status, agent inventory, provider connectivity,
   scheduled work, and backup freshness. Do not send a Telegram message or run
   a paid/side-effecting integration test without specific authorization.

Never commit runtime state, conversations, SQLite files, device identities,
authentication profiles, private keys, or host secrets. Test the complete
restore to staging at least quarterly and rehearse separate-card boot and
rollback before relying on the card swap procedure.

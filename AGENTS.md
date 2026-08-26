# OpenClaw Pi contributor guide

This repository provisions a Raspberry Pi 5 gateway with Ansible. Keep roles
idempotent and keep host policy in inventory/defaults, not inline constants.

## Layout

`playbooks/` orchestrates roles; `roles/` owns host configuration; `compose/`
contains SearXNG; `openclaw/` contains intentional, Git-managed templates;
`scripts/` contains local validation and operations; `docs/` contains runbooks.

## Security invariants

- Never commit secrets, private keys, production credentials, decrypted SOPS
  output, private workspace memory, or real machine-specific confidential data.
- `inventories/example` is illustrative. `inventories/production` is ignored
  except for its README. Production secrets belong in a SOPS-encrypted file.
- The gateway binds to loopback by default. SearXNG binds to loopback. Sandbox
  networking is `none`; containers are unprivileged with all capabilities dropped.
- Membership in the Docker group is root-equivalent. Any change to that trust
  boundary must be conspicuous in documentation and verification.
- Restores require explicit snapshot selection and overwrite confirmation.
- Release bootstrap must not require Git access on the Pi. Build bundles only
  from the tagged Git tree, publish checksums and provenance, reject unsafe
  archive entries, and preserve immutable installed release directories.

## Validation

Run `make check` before handing off. Useful focused commands are `make syntax`,
`make lint`, `make secrets-check`, and `make verify`. Hardware-dependent tests
must not be represented as passing unless they ran on the target Pi.

Use handlers for restarts, validate generated configuration before notifying
services, preserve SSH access while changing sshd/firewall policy, and document
every operational or trust-boundary change in README.md or `docs/`.

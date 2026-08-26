# OpenClaw Pi contributor guide

This repository provisions a Raspberry Pi 5 gateway with Ansible. Keep roles
idempotent and keep host policy in inventory/defaults, not inline constants.

## Layout

`playbooks/` orchestrates roles; `roles/` owns host configuration; `compose/`
contains SearXNG; `openclaw/` contains intentional, Git-managed templates;
`scripts/` contains local validation and operations; `docs/` contains runbooks.

## Git workflow

- Before changing files, inspect `git status --short --branch`, the applicable
  `AGENTS.md` files, and recent history. Preserve all unrelated tracked and
  untracked user work.
- Never make repository changes directly on `main`. Fetch the latest remote
  state, then create a new branch from `origin/main` unless the user names a
  different base. If pre-existing user changes prevent a safe branch switch,
  stop and ask rather than stashing, discarding, or relocating them.
- Use a short, descriptive, lowercase branch name with one of these prefixes:
  `feat/` for features, `fix/` for defects, `docs/` for documentation, `chore/`
  for maintenance, `refactor/` for behavior-preserving restructuring, or
  `security/` for security hardening. Do not reuse a merged branch.
- Keep commits focused and use imperative commit subjects that describe the
  outcome, such as `Add release bundle verification`. Do not amend, squash,
  rebase, force-push, or otherwise rewrite history unless the user explicitly
  requests it.
- Run the checks appropriate to the changed files before committing. Run
  `make check` for a complete handoff when locally practical, and report any
  checks that require unavailable tools, credentials, or Raspberry Pi hardware.
- When change work is complete and ready for review, verify the diff, confirm no
  secrets or unrelated files are included, create a focused commit, push the
  branch, and open a pull request. Do not leave completed work only in the local
  worktree unless the user explicitly asks you not to commit, push, or create a
  PR.
- Open pull requests against `main` unless directed otherwise. Give each PR a
  descriptive title and a body summarizing the change and checks run. Inspect CI
  after opening the PR and fix failures attributable to the change.
- Never merge or close a PR, delete remote branches, create tags or releases, or
  modify repository settings without explicit authorization.

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

# Bootstrap with curl

This is the operator runbook for provisioning a newly installed Raspberry Pi 5
from a versioned GitHub release. The safe workflow is download, verify, inspect,
then execute. Do not use `curl ... | sudo sh`; that executes bytes before they can
be authenticated or reviewed.

## 1. Prepare the Pi

Install current 64-bit Raspberry Pi OS, enable SSH using a public key, update the
OS, and confirm at least 4 GiB is free. The script independently verifies root
privileges, Raspberry Pi 5 hardware, `aarch64`, Raspberry Pi OS, DNS/networking,
and free space.

The repository intentionally excludes production inventory. Transfer these files
to the Pi over a trusted channel before running provisioning:

```text
/root/openclaw-inventory/hosts.yml
/root/openclaw-inventory/group_vars/all.yml
/root/openclaw-inventory/group_vars/secrets.sops.yml
```

All three should be root-owned and mode `0600`; their parent directories should
be `0700`. `secrets.sops.yml` must be valid SOPS ciphertext. If the Pi acts as the
Ansible controller, install SOPS from its verified upstream release and place the
corresponding age identity at `/root/.config/sops/age/keys.txt` with mode `0600`.
The identity must never enter Git, a release asset, shell history, or logs.

## 2. Download and authenticate the release asset

Set the release identity in local shell variables to reduce transcription errors:

```sh
OWNER=gromer
REPOSITORY=openclaw-pi
RELEASE=v1.0.0
BASE_URL="https://github.com/${OWNER}/${REPOSITORY}/releases/download/${RELEASE}"

curl --fail --silent --show-error --location --remote-name \
  "${BASE_URL}/bootstrap.sh"
curl --fail --silent --show-error --location --remote-name \
  "${BASE_URL}/bootstrap.sh.sha256"
sha256sum --check bootstrap.sh.sha256
```

The checksum proves that the two downloaded assets agree; it does not by itself
prove who published them. Verify the GitHub release page, tag, publisher, and
checksum through a trusted independent channel. Then inspect the script:

```sh
less bootstrap.sh
sh bootstrap.sh --help
```

Do not proceed if checksum verification fails. Delete both downloads, resolve the
release provenance problem, and download them again.

## 3. Validate without provisioning

Validation-only mode clones the requested immutable ref and runs repository
preflight/static validation without applying Ansible to the Pi:

```sh
sudo OPENCLAW_PI_REPO_URL=https://github.com/gromer/openclaw-pi.git \
  OPENCLAW_PI_REF=v1.0.0 \
  sh bootstrap.sh --validate-only
```

The repository ref is mandatory. Release tags and full commit SHAs are accepted;
common mutable branch names are rejected. Validation-only mode does not require a
production inventory.

## 4. Preview and provision

Run Ansible check/diff mode first:

```sh
sudo OPENCLAW_PI_REPO_URL=https://github.com/gromer/openclaw-pi.git \
  OPENCLAW_PI_REF=v1.0.0 \
  OPENCLAW_PI_INVENTORY=/root/openclaw-inventory/hosts.yml \
  sh bootstrap.sh --dry-run
```

Review the output, then provision using the same release and inventory:

```sh
sudo OPENCLAW_PI_REPO_URL=https://github.com/gromer/openclaw-pi.git \
  OPENCLAW_PI_REF=v1.0.0 \
  OPENCLAW_PI_INVENTORY=/root/openclaw-inventory/hosts.yml \
  sh bootstrap.sh
```

The default checkout is `/opt/openclaw-pi`. Override it with
`OPENCLAW_PI_DEST=/an/absolute/path` when necessary. The script installs Git,
Ansible Core, CA certificates, curl, and Make through apt; it does not accept
secrets as arguments. It reuses and updates a valid existing checkout, so the
same command is the supported rerun and upgrade path. To upgrade, substitute a
new reviewed immutable tag or commit.

## Private repositories

Configure root's SSH `known_hosts` and a narrowly scoped read-only deploy key
before bootstrap. Confirm access interactively, then use either form:

```sh
sudo OPENCLAW_PI_REPO_URL=git@github.com:OWNER/openclaw-pi.git \
  OPENCLAW_PI_REF=FULL_COMMIT_SHA \
  OPENCLAW_PI_INVENTORY=/root/openclaw-inventory/hosts.yml \
  sh bootstrap.sh
```

Do not embed a personal access token in an HTTPS URL. It can leak through process
inspection, shell history, terminal capture, or logs.

## Troubleshooting and cleanup

- `OPENCLAW_PI_REF must be an immutable tag or commit`: set a release tag or full
  SHA, not a branch name.
- `pre-staged production hosts.yml`: set `OPENCLAW_PI_INVENTORY` to the exact
  absolute inventory path and check root can read it.
- SOPS decryption failure: confirm `sops` is installed, the encrypted file is
  referenced by inventory, and the root-only age identity matches the committed
  public recipient.
- SSH clone failure: verify root's deploy key and pinned `known_hosts`; do not
  disable host-key verification.
- Inference reachability failure: test the inventory URL from the Pi and inspect
  the Mac firewall before rerunning.

The script leaves its versioned checkout in `/opt/openclaw-pi` by design. The two
downloaded release files can be retained for audit or removed after recording the
verified checksum. They contain no secrets.

# Bootstrap from a release bundle

This runbook provisions a newly installed Raspberry Pi 5 without cloning or
reading the Git repository. The recommended workflow is download, verify,
inspect, then execute. A convenience one-liner is also documented with its
weaker initial trust boundary.

## Release contents

The release workflow creates these assets from the exact tagged commit:

```text
install.sh
install.sh.sha256
bootstrap.sh
bootstrap.sh.sha256
openclaw-pi-<tag>.tar.gz
openclaw-pi-<tag>.tar.gz.sha256
release-manifest.json
release-manifest.json.sha256
```

The tarball contains the Ansible configuration, roles, Compose files, scripts,
tests, examples, and documentation. It excludes GitHub workflow metadata and all
untracked production data. The manifest identifies the tag, source commit,
archive name, and archive SHA-256.

## Guided installation from the latest release

Use this route for a fresh Pi with SSH already enabled and an Ollama server
reachable over the LAN. Download the latest published installer and checksum:

The release must have been published from a version containing `install.sh`.
GitHub does not retroactively add these assets to an older latest release.

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

Stop if checksum verification fails. The two assets originate from the same
GitHub release, so this detects corruption or mismatched assets but is not an
independent publisher signature. Confirm the release publisher and tag through
a trusted channel when that distinction matters.

The installer reads prompts from the terminal even when its script input is a
pipe. It asks only for the administrative account/key when they cannot be
inferred, the Ollama URL, and the exact advertised model. It then:

- resolves GitHub's `latest` redirect to an immutable tag and records that tag;
- independently verifies that tag's bootstrap and release-bundle checksums;
- creates `/root/openclaw-inventory` with mode `0700` and files with mode `0600`;
- installs the pinned SOPS binary after checking its upstream checksum;
- generates a root-only age identity and SOPS-encrypted random service secrets;
- tests Ollama reachability and confirms the model appears in `/api/tags`;
- provisions locally with Ansible and leaves Restic disabled until configured.

Back up `/root/.config/sops/age/keys.txt` securely and separately from the
encrypted inventory immediately after installation. Do not copy its private
contents into Git, chat, logs, or shell arguments.

This installer flow is the **convenience/local mode**: the Pi holds both the
encrypted inventory and the root-only private identity. That is easier to
operate but weaker against full host compromise, so offline identity backups are
mandatory.

The following convenience command is intentionally similar to common upstream
installers:

```sh
curl -fsSL https://github.com/gromer/openclaw-pi/releases/latest/download/install.sh | sudo sh
```

This is a single paste, but it executes network-delivered code as root before
you can inspect or separately authenticate that code. The inner bootstrap and
bundle are still checksum-verified. Prefer the preceding download-and-verify
workflow for production or any environment with meaningful credentials.

If all three inventory files already exist, rerunning the installer reuses them
instead of replacing them. A partial inventory is rejected. Set
`OPENCLAW_PI_RELEASE` to an immutable tag before running the installer when an
upgrade must target a specific version instead of the current published release.

## Manual bootstrap workflow

The remainder of this runbook describes the lower-level path for operators who
manage inventory and age identities themselves.

### SOPS custody modes

- **Convenience/local mode (install.sh):** the Pi stores
  `/root/.config/sops/age/keys.txt` and decrypts locally.
- **Controller mode (stronger):** the private identity stays off the Pi in
  encrypted offline custody. Keep only encrypted `secrets.sops.yml` on the Pi.
  If a local decrypt step is unavoidable, stage the identity root-only for the
  operation, then remove it.

For both modes, verify the active recipient before provisioning:

```sh
age-keygen -y /path/to/keys.txt
grep -n 'age1' .sops.yaml
```

The two values must match before decrypt/provision runs.

### 1. Prepare the Pi

Install current 64-bit Raspberry Pi OS, enable SSH using a public key, update the
OS, and confirm at least 4 GiB is free. The bootstrap independently verifies root
privileges, Raspberry Pi 5 hardware, `aarch64`, Raspberry Pi OS, and free space.

The release intentionally excludes production inventory. Transfer these files
to the Pi over a trusted channel:

```text
/root/openclaw-inventory/hosts.yml
/root/openclaw-inventory/group_vars/all.yml
/root/openclaw-inventory/group_vars/secrets.sops.yml
```

The files should be root-owned and mode `0600`; their parent directories should
be `0700`. `secrets.sops.yml` must be valid SOPS ciphertext. If the Pi is the
Ansible controller, install SOPS from its verified upstream release and place the
matching age identity at `/root/.config/sops/age/keys.txt` with mode `0600`.
Never put the identity in Git, a release asset, shell history, or logs.
If custody changes or an identity is exposed, rotate immediately: generate a new
identity, update `.sops.yaml` recipients, re-encrypt secrets, regenerate service
tokens, and rerun provisioning.

### 2. Download and authenticate bootstrap

Choose an existing release that contains a bundle. Replace `vX.Y.Z` below:

```sh
RELEASE=vX.Y.Z
BASE_URL="https://github.com/gromer/openclaw-pi/releases/download/${RELEASE}"

curl --fail --silent --show-error --location --remote-name \
  "${BASE_URL}/bootstrap.sh"
curl --fail --silent --show-error --location --remote-name \
  "${BASE_URL}/bootstrap.sh.sha256"
sha256sum --check bootstrap.sh.sha256
```

The checksum detects corruption or disagreement between the two assets; it does
not independently prove who published them. Verify the release page, tag,
publisher, and checksum using a trusted independent channel. Inspect the script:

```sh
less bootstrap.sh
sh bootstrap.sh --help
```

Stop if verification fails. Do not execute or modify the downloaded script.

### 3. Validate without provisioning

Validation-only mode downloads and authenticates the full release bundle,
installs it version-by-version, then performs dependency-light syntax and
structural checks without applying Ansible:

```sh
sudo OPENCLAW_PI_RELEASE="$RELEASE" sh bootstrap.sh --validate-only
```

The script derives the asset URL from the release and the default repository
`gromer/openclaw-pi`. No Git client, checkout, deploy key, or GitHub API token is
needed.

### 4. Preview and provision

Run Ansible check/diff mode first:

```sh
sudo OPENCLAW_PI_RELEASE="$RELEASE" \
  OPENCLAW_PI_INVENTORY=/root/openclaw-inventory/hosts.yml \
  sh bootstrap.sh --dry-run
```

Review the output, then provision with the same release and inventory:

```sh
sudo OPENCLAW_PI_RELEASE="$RELEASE" \
  OPENCLAW_PI_INVENTORY=/root/openclaw-inventory/hosts.yml \
  sh bootstrap.sh
```

The bootstrap installs only Ansible Core, CA certificates, curl, Make, and tar
through apt. It downloads the archive and checksum over HTTPS, verifies SHA-256,
and rejects absolute paths, path traversal, symbolic links, and hard links before
extraction.

## Installation and rollback model

Releases are immutable and installed as:

```text
/opt/openclaw-pi/
├── current -> releases/vX.Y.Z
└── releases/
    ├── vX.Y.Z/
    └── previous-version/
```

The `current` link is replaced atomically only after verification and extraction
succeed. Rerunning the same release is safe: its downloaded checksum must match
the installed checksum marker. The script refuses to overwrite an existing tag
whose content differs.

To upgrade, download the new release's `bootstrap.sh` and checksum, verify them,
and run with the new tag. To roll back code, rerun the bootstrap from the older
release with that older immutable tag. Ansible may not reverse data migrations;
restore mutable state from Restic when the release notes require it.

## Mirrors and private releases

For another public fork, set its GitHub repository slug:

```sh
sudo OPENCLAW_PI_RELEASE="$RELEASE" \
  OPENCLAW_PI_REPOSITORY=OWNER/REPOSITORY \
  OPENCLAW_PI_INVENTORY=/root/openclaw-inventory/hosts.yml \
  sh bootstrap.sh
```

For a private release, download all six assets through an authenticated process,
publish them unchanged to a controlled HTTPS origin, and set the directory URL:

```sh
sudo OPENCLAW_PI_RELEASE="$RELEASE" \
  OPENCLAW_PI_ASSET_BASE_URL=https://artifacts.example/openclaw-pi/vX.Y.Z \
  OPENCLAW_PI_INVENTORY=/root/openclaw-inventory/hosts.yml \
  sh bootstrap.sh
```

Do not embed access tokens in URLs. The mirror must preserve the original asset
names and bytes. Verify its checksums against GitHub through an independent
channel.

## Troubleshooting and cleanup

- `OPENCLAW_PI_RELEASE is required`: supply the exact published tag.
- HTTP 404 for the archive: the selected release predates release bundles or its
  asset workflow failed. Inspect the release assets and Actions run.
- Checksum failure: do not retry execution; remove the downloads and investigate
  release or mirror integrity.
- Existing release checksum differs: do not delete or overwrite it blindly.
  Inspect the installed tree and release provenance for tampering or tag reuse.
- Production inventory error: set `OPENCLAW_PI_INVENTORY` to the absolute
  `hosts.yml` path and confirm root can read it.
- SOPS failure: confirm SOPS is installed, `secrets_file` points to the encrypted
  file, and the root-only age identity matches the configured public recipient.
- Identity compromise response: rotate the age identity and application secrets
  immediately, then reprovision and invalidate any leaked credentials.
- Inference failure: test the inventory endpoint from the Pi and inspect the Mac
  firewall before rerunning.

Temporary downloads are removed automatically. Installed releases remain under
`/opt/openclaw-pi/releases` for audit and deliberate rollback. Do not manually
delete the target of `current` while provisioning is active.

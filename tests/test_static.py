#!/usr/bin/env python3
"""Credential-free invariants suitable for non-ARM CI."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
config = (ROOT / "roles/openclaw/templates/openclaw.json.j2").read_text()
unit = (ROOT / "roles/openclaw/templates/openclaw.service.j2").read_text()
compose = (ROOT / "roles/searxng/templates/compose.yml.j2").read_text()
bootstrap = (ROOT / "bootstrap.sh").read_text()
installer = (ROOT / "install.sh").read_text()
assert '"network":"{{ sandbox_network }}"' in config
assert '"capDrop":["ALL"]' in config
assert '"readOnlyRoot":true' in config
assert "SupplementaryGroups=docker" in unit
assert "NoNewPrivileges=true" in unit
assert '"{{ searxng_bind_address }}:{{ searxng_port }}:8080"' in compose
assert "git clone" not in bootstrap
assert "openclaw-pi-${RELEASE}.tar.gz" in bootstrap
assert "sha256sum --check" in bootstrap
assert 'tar -tzf "$ARCHIVE_PATH"' in bootstrap
assert "releases/latest" in installer
assert "sha256sum --check bootstrap.sh.sha256" in installer
assert "SOPS_AGE_KEY_FILE" in installer
assert "ansible_connection: local" in installer
print("static security invariants: ok")

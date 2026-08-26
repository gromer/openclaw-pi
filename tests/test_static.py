#!/usr/bin/env python3
"""Credential-free invariants suitable for non-ARM CI."""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
config = (ROOT / "roles/openclaw/templates/openclaw.json.j2").read_text()
unit = (ROOT / "roles/openclaw/templates/openclaw.service.j2").read_text()
compose = (ROOT / "roles/searxng/templates/compose.yml.j2").read_text()
assert '"network":"{{ sandbox_network }}"' in config
assert '"capDrop":["ALL"]' in config
assert '"readOnlyRoot":true' in config
assert "SupplementaryGroups=docker" in unit
assert "NoNewPrivileges=true" in unit
assert '"{{ searxng_bind_address }}:{{ searxng_port }}:8080"' in compose
print("static security invariants: ok")


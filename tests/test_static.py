#!/usr/bin/env python3
"""Credential-free invariants suitable for non-ARM CI."""
import json
import pathlib

import jinja2

ROOT = pathlib.Path(__file__).resolve().parents[1]
config = (ROOT / "roles/openclaw/templates/openclaw.json.j2").read_text()
environment = (ROOT / "roles/openclaw/templates/environment.j2").read_text()
unit = (ROOT / "roles/openclaw/templates/openclaw.service.j2").read_text()
compose = (ROOT / "roles/searxng/templates/compose.yml.j2").read_text()
bootstrap = (ROOT / "bootstrap.sh").read_text()
installer = (ROOT / "install.sh").read_text()
release_workflow = (ROOT / ".github/workflows/release.yml").read_text()
assert '"network":{{ sandbox_network | to_json }}' in config
assert '"capDrop":["ALL"]' in config
assert '"readOnlyRoot":true' in config
assert "| replace('\\\\', '\\\\\\\\') | replace('\"', '\\\\\"') }}" in environment
assert "SupplementaryGroups=docker" in unit
assert "NoNewPrivileges=true" in unit
assert '"{{ searxng_bind_address }}:{{ searxng_port }}:8080"' in compose
assert "git clone" not in bootstrap
assert "openclaw-pi-${RELEASE}.tar.gz" in bootstrap
assert "sha256sum --check" in bootstrap
assert 'tar -tzf "$ARCHIVE_PATH"' in bootstrap
assert "releases/latest" in installer
assert "Selected release tag:" in installer
assert "Selected immutable release:" not in installer
assert "sha256sum --check bootstrap.sh.sha256" in installer
assert "SOPS_AGE_KEY_FILE" in installer
assert "ansible_connection: local" in installer
assert "--clobber" not in release_workflow
assert "gh release create" in release_workflow
assert "--draft --verify-tag" in release_workflow
assert "gh release edit \"$RELEASE_TAG\" --draft=false" in release_workflow
assert "attest-build-provenance" in release_workflow

jinja_env = jinja2.Environment(undefined=jinja2.StrictUndefined)
jinja_env.filters["to_json"] = json.dumps

shared = {
    "openclaw_gateway_bind": "127.0.0.1",
    "openclaw_gateway_port": 18789,
    "inference_base_url": "http://localhost:11434/v1 with space",
    "inference_timeout_seconds": 300,
    "inference_model": 'model "quoted" \\ and spaced',
    "inference_context_window": 32768,
    "inference_max_tokens": 8192,
    "openclaw_workspace_dir": "/var/lib/openclaw/work space",
    "sandbox_mode": "all",
    "sandbox_scope": "agent scope",
    "sandbox_workspace_access": "ro",
    "sandbox_image": "openclaw-sandbox:bookworm\\slim",
    "sandbox_network": "none",
    "sandbox_pids_limit": 128,
    "sandbox_memory": "1g",
    "sandbox_memory_swap": "1g",
    "sandbox_cpus": 1,
    "sandbox_nofile_soft": 1024,
    "sandbox_nofile_hard": 2048,
}

mlx_provider = 'mlx provider "β"/edge\\lane'
mlx_rendered = jinja_env.from_string(config).render(
    {
        **shared,
        "inference_backend": "mlx_openai",
        "openclaw_provider_id": mlx_provider,
    }
)
mlx_config = json.loads(mlx_rendered)
assert mlx_provider in mlx_config["models"]["providers"]
assert mlx_config["models"]["providers"][mlx_provider]["models"][0]["id"] == shared["inference_model"]
assert mlx_config["agents"]["defaults"]["model"]["primary"] == f"{mlx_provider}/{shared['inference_model']}"

ollama_rendered = jinja_env.from_string(config).render(
    {
        **shared,
        "inference_backend": "ollama",
        "openclaw_provider_id": "unused-for-ollama",
    }
)
ollama_config = json.loads(ollama_rendered)
assert ollama_config["models"]["providers"]["ollama"]["models"][0]["name"] == shared["inference_model"]

env_rendered = jinja_env.from_string(environment).render(
    {
        "openclaw_secrets": {
            "gateway_token": 'tok "quoted" \\ spaced',
            "inference_api_key": 'api "quoted" \\ key',
        }
    }
)
assert 'OPENCLAW_GATEWAY_TOKEN="tok \\"quoted\\" \\\\ spaced"' in env_rendered
assert 'INFERENCE_API_KEY="api \\"quoted\\" \\\\ key"' in env_rendered

# Restore script must use the correct plural 'restic snapshots' command.
restore_sh = (ROOT / "scripts/restore.sh").read_text()
assert "restic snapshots" in restore_sh, "restore.sh must call 'restic snapshots' (plural)"
assert "restic snapshot " not in restore_sh, "restore.sh must not call 'restic snapshot' (singular)"

# Backup template must fail-closed on repo errors instead of always running init.
backup_j2 = (ROOT / "roles/restic/templates/backup.sh.j2").read_text()
assert "restic snapshots" in backup_j2, "backup.sh.j2 must probe with 'restic snapshots'"
assert "restic_exit" in backup_j2, "backup.sh.j2 must check exit code before running restic init"
assert "restic snapshots >/dev/null 2>&1 || restic init" not in backup_j2, \
    "backup.sh.j2 must not unconditionally init on any snapshots failure"

# Backup template must acquire a lock to serialise operations.
assert "flock" in backup_j2, "backup.sh.j2 must use flock to serialise backup/prune"

# Freshness service template must be present and reference the environment file.
freshness_svc = (ROOT / "roles/restic/templates/freshness.service.j2").read_text()
assert "restic_environment_path" in freshness_svc, "freshness.service.j2 must reference restic_environment_path"
assert "openclaw-backup-freshness" in freshness_svc, "freshness.service.j2 must reference the helper script"

print("static security invariants: ok")

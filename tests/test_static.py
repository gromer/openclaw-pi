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
sandbox_dockerfile = (ROOT / "roles/sandbox/files/Dockerfile").read_text()
openclaw_tasks = (ROOT / "roles/openclaw/tasks/main.yml").read_text()
docker_tasks = (ROOT / "roles/docker/tasks/main.yml").read_text()
security_tasks = (ROOT / "roles/security/tasks/main.yml").read_text()
example_inventory = (ROOT / "inventories/example/group_vars/all.yml").read_text()
bootstrap = (ROOT / "bootstrap.sh").read_text()
installer = (ROOT / "install.sh").read_text()
release_workflow_path = ROOT / ".github/workflows/release.yml"
assert '"network":{{ sandbox_network | to_json }}' in config
assert '"capDrop":["ALL"]' in config
assert '"readOnlyRoot":true' in config
assert '"allowedOrigins":{{ openclaw_control_ui_allowed_origins | to_json }}' in config
assert "| replace('\\\\', '\\\\\\\\') | replace('\"', '\\\\\"') }}" in environment
assert "SupplementaryGroups=docker" in unit
assert "NoNewPrivileges=true" in unit
assert '"{{ searxng_bind_address }}:{{ searxng_port }}:8080"' in compose
assert "git clone" not in bootstrap
assert "openclaw-pi-${RELEASE}.tar.gz" in bootstrap
assert "sha256sum --check" in bootstrap
assert 'case " ${ID:-} ${ID_LIKE:-} " in' in bootstrap
assert '*" debian "*|*" raspbian "*)' in bootstrap
assert 'tar -tzf "$ARCHIVE_PATH"' in bootstrap
assert "releases/latest" in installer
assert "Selected release tag:" in installer
assert "Selected immutable release:" not in installer
assert "sha256sum --check bootstrap.sh.sha256" in installer
assert "SOPS_AGE_KEY_FILE" in installer
assert "ansible_connection: local" in installer
if release_workflow_path.exists():
    release_workflow = release_workflow_path.read_text()
    assert "--clobber" not in release_workflow
    assert "gh release create" in release_workflow
    assert "--draft --verify-tag" in release_workflow
    assert "gh release edit \"$RELEASE_TAG\" --draft=false" in release_workflow
    assert "dist/release-manifest.json" in release_workflow
    assert "dist/release-manifest.json.sha256" in release_workflow
assert "@sha256:" in sandbox_dockerfile, "sandbox base image must be digest pinned"
assert "setup_{{ node_major }}.x" not in openclaw_tasks, "NodeSource setup scripts must not execute as root"
assert "openclaw_npm_integrity_actual.stdout == openclaw_npm_integrity" in openclaw_tasks
assert "openclaw_nodesource_key_fingerprint not in openclaw_nodesource_key_info.stdout" in openclaw_tasks
assert "6F71F525282841EEDAF851B42F59B5F99B1BE0B4" in (ROOT / "roles/openclaw/defaults/main.yml").read_text()
assert "docker_apt_key_fingerprint not in docker_key_info.stdout" in docker_tasks
assert "--homedir" in docker_tasks, "Docker key verification must not depend on root's home"
assert "--homedir" in openclaw_tasks, "NodeSource key verification must not depend on root's home"
assert "[docker, version]" in docker_tasks, "Docker daemon access must be verified"
assert "[docker, buildx, version]" in docker_tasks, "Docker Buildx must be verified"
assert "[docker, compose, version]" in docker_tasks, "Docker Compose must be verified"
assert 'become_user: "{{ openclaw_user }}"' in docker_tasks, \
    "Docker access must be verified as the OpenClaw account"
assert "openclaw_gateway_bind: lan" in example_inventory
assert "security_gateway_allowed_cidrs:" in example_inventory
assert "to any port {{ openclaw_gateway_port }}" in security_tasks
verification_tasks = (ROOT / "roles/verification/tasks/main.yml").read_text()
common_tasks = (ROOT / "roles/common/tasks/main.yml").read_text()
assert "retries: 12" in verification_tasks
assert "until: verification_searxng_health.status == 200" in verification_tasks
assert "127.0.1.1 {{ pi_hostname }}" in common_tasks

jinja_env = jinja2.Environment(undefined=jinja2.StrictUndefined)
jinja_env.filters["to_json"] = json.dumps

shared = {
    "openclaw_gateway_bind": "127.0.0.1",
    "openclaw_gateway_port": 18789,
    "openclaw_control_ui_allowed_origins": ["http://192.0.2.10:18789"],
    "inference_base_url": "http://localhost:11434/v1 with space",
    "inference_timeout_seconds": 300,
    "inference_model": 'model "quoted" \\ and spaced',
    "inference_context_window": 32768,
    "inference_max_tokens": 8192,
    "openrouter_model_ref": "openrouter/auto-beta",
    "openrouter_model_name": "OpenRouter Auto (Beta)",
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
assert f"{mlx_provider}/{shared['inference_model']}" in mlx_config["agents"]["defaults"]["models"]

ollama_rendered = jinja_env.from_string(config).render(
    {
        **shared,
        "inference_backend": "ollama",
        "openclaw_provider_id": "unused-for-ollama",
    }
)
ollama_config = json.loads(ollama_rendered)
assert ollama_config["models"]["providers"]["ollama"]["models"][0]["name"] == shared["inference_model"]
assert f"ollama/{shared['inference_model']}" in ollama_config["agents"]["defaults"]["models"]

for rendered_config in (mlx_config, ollama_config):
    openrouter_model = rendered_config["models"]["providers"]["openrouter"]["models"][0]
    assert openrouter_model["id"] == "openrouter/auto-beta"
    assert openrouter_model["name"] == "OpenRouter Auto (Beta)"
    assert rendered_config["agents"]["defaults"]["models"][
        "openrouter/auto-beta"
    ]["alias"] == "OpenRouter Auto (Beta)"

env_rendered = jinja_env.from_string(environment).render(
    {
        "openclaw_secrets": {
            "gateway_token": 'tok "quoted" \\ spaced',
            "inference_api_key": 'api "quoted" \\ key',
            "openrouter_api_key": 'router "quoted" \\ key',
        }
    }
)
assert 'OPENCLAW_GATEWAY_TOKEN="tok \\"quoted\\" \\\\ spaced"' in env_rendered
assert 'INFERENCE_API_KEY="api \\"quoted\\" \\\\ key"' in env_rendered
assert 'OPENROUTER_API_KEY="router \\"quoted\\" \\\\ key"' in env_rendered

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

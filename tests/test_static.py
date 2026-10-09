#!/usr/bin/env python3
"""Credential-free invariants suitable for non-ARM CI."""
import json
import pathlib

import jinja2

ROOT = pathlib.Path(__file__).resolve().parents[1]
config = (ROOT / "roles/openclaw/templates/openclaw.json.j2").read_text()
environment = (ROOT / "roles/openclaw/templates/environment.j2").read_text()
unit = (ROOT / "roles/openclaw/templates/openclaw.service.j2").read_text()
firecrawl_dropin = (ROOT / "roles/openclaw/templates/firecrawl-env.conf.j2").read_text()
compose = (ROOT / "roles/searxng/templates/compose.yml.j2").read_text()
sandbox_dockerfile = (ROOT / "roles/sandbox/files/Dockerfile").read_text()
openclaw_tasks = (ROOT / "roles/openclaw/tasks/main.yml").read_text()
openclaw_config_tasks = (ROOT / "roles/openclaw/tasks/configuration.yml").read_text()
openclaw_workspace_tasks = (ROOT / "roles/openclaw/tasks/workspaces.yml").read_text()
user_tasks = (ROOT / "roles/users/tasks/main.yml").read_text()
docker_tasks = (ROOT / "roles/docker/tasks/main.yml").read_text()
security_tasks = (ROOT / "roles/security/tasks/main.yml").read_text()
example_inventory = (ROOT / "inventories/example/group_vars/all.yml").read_text()
bootstrap = (ROOT / "bootstrap.sh").read_text()
installer = (ROOT / "install.sh").read_text()

assert '"source": "file"' in config
assert '"id": "/GATEWAY_AUTH_TOKEN"' in config
assert '"path": {{ openclaw_gateway_token_file | to_json }}' in config
assert '"provider": "ollama_caddy_file"' in config
assert '"id": "/OLLAMA_CADDY_TOKEN"' in config
assert '"allowlist": ["FIRECRAWL_API_KEY"]' in config
assert 'dest: /usr/local/bin/openclaw' in openclaw_tasks
assert 'OPENCLAW_GATEWAY_TOKEN' not in environment
assert "Restart=always" in unit
assert "WantedBy=default.target" in unit
assert "NoNewPrivileges=true" in unit
assert "LockPersonality=true" in unit
assert "RestrictRealtime=true" in unit
assert "RestrictSUIDSGID=true" in unit
assert "SystemCallArchitectures=native" in unit
assert "PrivateTmp=true" not in unit
assert "EnvironmentFile={{ firecrawl_environment_path }}" in firecrawl_dropin
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
assert 'gateway_token=$(openssl rand' not in installer
assert 'gateway-token.json' in installer
assert "openclaw_installed.stdout | trim != openclaw_version" in openclaw_tasks
assert "when: not openclaw_config_existing.stat.exists" in openclaw_config_tasks
assert "config validate" in openclaw_config_tasks
assert 'OPENCLAW_CONFIG_PATH: "{{ openclaw_config_candidate.path }}"' in openclaw_config_tasks
assert "force: false" in openclaw_workspace_tasks
assert "groups: \"{{ admin_groups | join(',') }}\"" not in user_tasks.split(
    "- name: Create OpenClaw service account", 1
)[1].split("- name: Create OpenClaw directories", 1)[0]
service_group_task = user_tasks.split("- name: Create OpenClaw service group", 1)[1].split(
    "- name: Create administrator SSH directory", 1
)[0]
assert "name: \"{{ openclaw_group }}\"" in service_group_task
assert "when:" not in service_group_task
assert "inference_base_url == 'https://ollama.gromer.dev'" in openclaw_tasks
assert "verification_user_manager_groups.stdout.split()" in (
    ROOT / "roles/verification/tasks/main.yml"
).read_text()
assert "/etc/systemd/system/openclaw.service" not in openclaw_tasks

release_workflow_path = ROOT / ".github/workflows/release.yml"
if release_workflow_path.exists():
    release_workflow = release_workflow_path.read_text()
    assert "--clobber" not in release_workflow
    assert "gh release create" in release_workflow
    assert "--draft --verify-tag" in release_workflow
    assert 'gh release edit "$RELEASE_TAG" --draft=false' in release_workflow
    assert "dist/release-manifest.json" in release_workflow
    assert "dist/release-manifest.json.sha256" in release_workflow

assert "@sha256:" in sandbox_dockerfile
assert "setup_{{ node_major }}.x" not in openclaw_tasks
assert "openclaw_npm_integrity_actual.stdout == openclaw_npm_integrity" in openclaw_tasks
assert "openclaw_nodesource_key_fingerprint not in openclaw_nodesource_key_info.stdout" in openclaw_tasks
assert "6F71F525282841EEDAF851B42F59B5F99B1BE0B4" in (ROOT / "roles/openclaw/defaults/main.yml").read_text()
assert "docker_apt_key_fingerprint not in docker_key_info.stdout" in docker_tasks
assert "--homedir" in docker_tasks
assert "--homedir" in openclaw_tasks
for requirement in ("[docker, version]", "[docker, buildx, version]", "[docker, compose, version]"):
    assert requirement in docker_tasks
assert 'become_user: "{{ openclaw_user }}"' in docker_tasks
assert "openclaw_gateway_bind: lan" in example_inventory
assert "security_gateway_allowed_cidrs:" in example_inventory
assert "to any port {{ openclaw_gateway_port }}" in security_tasks

verification_tasks = (ROOT / "roles/verification/tasks/main.yml").read_text()
common_tasks = (ROOT / "roles/common/tasks/main.yml").read_text()
assert "retries: 12" in verification_tasks
assert "until: verification_searxng_health.status == 200" in verification_tasks
assert "UnitFileState=enabled" in verification_tasks
assert "127.0.1.1 {{ pi_hostname }}" in common_tasks

jinja_env = jinja2.Environment(undefined=jinja2.StrictUndefined)
jinja_env.filters["to_json"] = json.dumps
shared = {
    "openclaw_gateway_bind": "127.0.0.1",
    "openclaw_gateway_port": 18789,
    "openclaw_control_ui_allowed_origins": ["http://192.0.2.10:18789"],
    "openclaw_gateway_token_file": "/home/gromer/.config/openclaw/secrets/gateway-token.json",
    "ollama_token_file": "/home/gromer/.config/openclaw/secrets/ollama-caddy-token.json",
    "firecrawl_secret_enabled": False,
    "inference_backend": "ollama",
    "inference_base_url": "https://ollama.gromer.dev",
    "inference_model": "gemma4:26b-mlx",
    "inference_timeout_seconds": 300,
    "inference_context_window": 32768,
    "inference_max_tokens": 8192,
    "openclaw_workspace_dir": "/home/gromer/.openclaw/workspace",
    "sandbox_mode": "all",
    "sandbox_scope": "agent",
    "sandbox_workspace_access": "none",
    "sandbox_image": "openclaw-sandbox:bookworm-slim",
    "sandbox_network": "none",
    "sandbox_pids_limit": 128,
    "sandbox_memory": "1g",
    "sandbox_memory_swap": "1g",
    "sandbox_cpus": 1,
    "sandbox_nofile_soft": 1024,
    "sandbox_nofile_hard": 2048,
}
seed = json.loads(jinja_env.from_string(config).render(shared))
assert seed["gateway"]["controlUi"]["allowedOrigins"] == shared["openclaw_control_ui_allowed_origins"]
assert seed["gateway"]["auth"]["token"] == {
    "source": "file", "provider": "gateway_token_file", "id": "/GATEWAY_AUTH_TOKEN"
}
assert seed["models"]["providers"]["ollama"]["api"] == "ollama"
assert seed["models"]["providers"]["ollama"]["apiKey"] == {
    "source": "file", "provider": "ollama_caddy_file", "id": "/OLLAMA_CADDY_TOKEN"
}
assert seed["agents"]["defaults"]["model"]["primary"] == "ollama/gemma4:26b-mlx"

special_model = 'model "quoted" \\ and spaced'
special = json.loads(
    jinja_env.from_string(config).render({**shared, "inference_model": special_model})
)
assert special["models"]["providers"]["ollama"]["models"][0]["id"] == special_model
assert special["agents"]["defaults"]["model"]["primary"] == f"ollama/{special_model}"

firecrawl = json.loads(
    jinja_env.from_string(config).render({**shared, "firecrawl_secret_enabled": True})
)
assert firecrawl["secrets"]["providers"]["firecrawl_env"] == {
    "source": "env", "allowlist": ["FIRECRAWL_API_KEY"]
}
assert firecrawl["plugins"]["entries"]["firecrawl"]["config"]["webSearch"]["apiKey"] == {
    "source": "env", "provider": "firecrawl_env", "id": "FIRECRAWL_API_KEY"
}

env_rendered = jinja_env.from_string(environment).render(
    {"openclaw_secrets": {
        "inference_api_key": 'api "quoted" \\ key',
        "openrouter_api_key": 'router "quoted" \\ key',
    }}
)
assert "OPENCLAW_GATEWAY_TOKEN" not in env_rendered
assert 'INFERENCE_API_KEY="api \\"quoted\\" \\\\ key"' in env_rendered
assert 'OPENROUTER_API_KEY="router \\"quoted\\" \\\\ key"' in env_rendered

restore_sh = (ROOT / "scripts/restore.sh").read_text()
assert "restic snapshots" in restore_sh
assert "restic snapshot " not in restore_sh
backup_j2 = (ROOT / "roles/restic/templates/backup.sh.j2").read_text()
assert "restic snapshots" in backup_j2 and "restic_exit" in backup_j2
assert "restic snapshots >/dev/null 2>&1 || restic init" not in backup_j2
assert "flock" in backup_j2 and "systemctl --user" in backup_j2
assert "LoadState" in backup_j2 and "refusing an unquiesced snapshot" in backup_j2
freshness_svc = (ROOT / "roles/restic/templates/freshness.service.j2").read_text()
assert "restic_environment_path" in freshness_svc
assert "openclaw-backup-freshness" in freshness_svc

print("static security invariants: ok")

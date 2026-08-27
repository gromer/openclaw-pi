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
assert "sha256sum --check bootstrap.sh.sha256" in installer
assert "SOPS_AGE_KEY_FILE" in installer
assert "ansible_connection: local" in installer

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
print("static security invariants: ok")

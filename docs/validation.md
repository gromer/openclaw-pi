# Validation scope

`make check` covers shell syntax/ShellCheck, YAML lint, Ansible syntax/lint,
template-variable consistency, Compose parsing, and likely plaintext secrets.
GitHub Actions runs the same credential-free checks against example inventory.

`make diff`, provisioning, systemd hardening compatibility, ARM64 image pulls,
endpoint reachability, service health, sandbox creation/isolation, Restic backend
access, backup freshness, and restoration require the actual Pi, Mac, or backup
backend. CI does not pretend to model those systems.


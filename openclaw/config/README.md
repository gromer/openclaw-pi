# Managed configuration

The first-install gateway seed lives in `roles/openclaw/templates/`. Do not
place rendered configuration or credentials here. The deployed application
config is `/home/gromer/.openclaw/openclaw.json`; Ansible does not replace it
after creation.


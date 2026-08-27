SHELL := /bin/sh
INVENTORY ?= inventories/production/hosts.yml
PLAYBOOK ?= playbooks/site.yml
ANSIBLE_ARGS ?=
.DEFAULT_GOAL := help
.PHONY: help bootstrap deps preflight provision validate check syntax lint diff verify backup restore secrets-init secrets-edit secrets-check dependency-policy-check backup-check compose-check release-test actions-policy-check
help: ## Show targets
	@awk 'BEGIN{FS=":.*## "}/^[a-zA-Z0-9_-]+:.*## /{printf "%-18s %s\n",$$1,$$2}' $(MAKEFILE_LIST)
bootstrap: ## Validate the bootstrap script locally
	sh -n bootstrap.sh install.sh scripts/*.sh tests/*.sh
	shellcheck bootstrap.sh install.sh scripts/*.sh tests/*.sh
deps: ## Install declared Ansible dependencies
	ansible-galaxy install -r requirements.yml
preflight: ## Check controller prerequisites
	./scripts/preflight.sh
provision: ## Provision the production inventory
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) $(ANSIBLE_ARGS)
validate: syntax compose-check secrets-check actions-policy-check dependency-policy-check release-test ## Run credential-free structural validation
	python3 scripts/validate-vars.py
	python3 tests/test_static.py
actions-policy-check: ## Check immutable CI actions, runners, and image pins
	./scripts/actions-policy-check.sh
dependency-policy-check: ## Check that CI dependencies remain exactly pinned
	./scripts/dependency-policy-check.sh
check: validate lint bootstrap ## Run all local static checks
syntax: ## Run Ansible syntax check against safe example inventory
	ansible-playbook -i inventories/example/hosts.yml $(PLAYBOOK) --syntax-check
lint: ## Run YAML and Ansible linters
	yamllint . && ansible-lint $(PLAYBOOK)
diff: ## Preview production changes (no apply)
	ansible-playbook -i $(INVENTORY) $(PLAYBOOK) --check --diff $(ANSIBLE_ARGS)
verify: ## Run post-provision role against production
	ansible-playbook -i $(INVENTORY) playbooks/verify.yml $(ANSIBLE_ARGS)
backup: ## Start a backup on the Pi
	ansible all -i $(INVENTORY) -b -m command -a 'systemctl start openclaw-backup.service'
restore: ## Restore explicit SNAPSHOT into TARGET; never defaults to latest
	@test -n "$(SNAPSHOT)" -a -n "$(TARGET)" || (echo 'set SNAPSHOT and TARGET' >&2; exit 2)
	./scripts/restore.sh "$(SNAPSHOT)" "$(TARGET)" $(CONFIRM)
secrets-init: ## Create/edit encrypted production secrets after configuring recipient
	@test -z "$(shell grep REPLACE_WITH .sops.yaml)" || (echo 'replace age recipient first' >&2; exit 1)
	SOPS_AGE_KEY_FILE="$${SOPS_AGE_KEY_FILE:?set SOPS_AGE_KEY_FILE}" sops inventories/production/group_vars/secrets.sops.yml
secrets-edit: ## Edit encrypted production secrets
	sops inventories/production/group_vars/secrets.sops.yml
secrets-check: ## Scan tracked content for likely plaintext secrets
	./scripts/secrets-check.sh
backup-check: ## Check repository and snapshot freshness using current Restic environment
	restic check && ./scripts/backup-freshness.sh
compose-check: ## Validate committed Compose reference
	docker compose -f compose/searxng/compose.yml config --quiet
release-test: ## Build and inspect a disposable release bundle
	./tests/test-release-assets.sh

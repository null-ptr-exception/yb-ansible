.PHONY: help test test-static test-controller test-docker-integration test-molecule

MOLECULE_SCENARIOS ?= default xcluster backup-restore
ANSIBLE_PLAYBOOK ?= ansible-playbook
STATIC_TESTS := \
	tests/test_rhel8_yb_build_config.sh \
	tests/test_run_molecule_scenarios.sh \
	tests/test_static_verifiers_without_rg.sh \
	tests/test_yb_shipper_2025_build.sh \
	tests/verify_ansible_builtin_fqcn.sh \
	tests/verify_external_download_integrity.sh \
	tests/verify_molecule_ssh_key.sh \
	tests/verify_playbook_service_names.sh \
	tests/verify_test_entrypoints.sh \
	tests/verify_xcluster_replication_id.sh

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-20s %s\n", $$1, $$2}'

test: test-static test-controller test-molecule ## Run all tests

test-static: ## Run fast shell and Ansible syntax checks
	@for test in $(STATIC_TESTS); do bash "$$test"; done
	@$(ANSIBLE_PLAYBOOK) --syntax-check tests/syntax_check.yml

test-controller: ## Build and verify the controller Docker image
	@controller/test.sh

test-docker-integration: ## Run Docker Compose integration tests
	@tests/verify_docker_xcluster.sh
	@tests/verify_backup_restore.sh

test-molecule: ## Run molecule scenarios (requires libvirt)
	@MOLECULE_SCENARIOS="$(MOLECULE_SCENARIOS)" tests/run_molecule_scenarios.sh

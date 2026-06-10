.PHONY: help test test-controller test-molecule

MOLECULE_SCENARIOS ?= default xcluster backup-restore

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-20s %s\n", $$1, $$2}'

test: test-controller test-molecule ## Run all tests

test-controller: ## Build and verify the controller Docker image
	@controller/test.sh

test-molecule: ## Run molecule scenarios (requires libvirt)
	@MOLECULE_SCENARIOS="$(MOLECULE_SCENARIOS)" tests/run_molecule_scenarios.sh

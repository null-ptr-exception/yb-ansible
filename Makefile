.PHONY: help test test-controller test-molecule

MOLECULE_SCENARIOS ?= default xcluster backup-restore

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-20s %s\n", $$1, $$2}'

test: test-controller test-molecule ## Run all tests

test-controller: ## Build and verify the controller Docker image
	@controller/test.sh

test-molecule: ## Run molecule scenarios (requires libvirt)
	@for scenario in $(MOLECULE_SCENARIOS); do \
		echo "==> molecule test -s $$scenario"; \
		molecule test -s $$scenario || exit 1; \
	done

.PHONY: help test test-controller test-molecule

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-20s %s\n", $$1, $$2}'

test: test-controller test-molecule ## Run all tests

test-controller: ## Build and verify the controller Docker image
	@controller/test.sh

test-molecule: ## Run molecule test (requires libvirt)
	@molecule test

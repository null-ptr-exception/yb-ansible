.PHONY: help test test-controller test-molecule test-centos7

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-20s %s\n", $$1, $$2}'

test: test-controller test-molecule ## Run all tests

test-controller: ## Build and verify the controller Docker image
	@controller/test.sh

test-molecule: ## Run molecule test (requires libvirt)
	@molecule test

test-centos7: ## Run molecule test with CentOS 7 (requires libvirt)
	@molecule test -s centos7

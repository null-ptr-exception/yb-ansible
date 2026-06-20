#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"

  grep -Eq -- "$pattern" "$file" || fail "$file does not contain pattern: $pattern"
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"

  if grep -Eq -- "$pattern" "$file"; then
    fail "$file contains forbidden pattern: $pattern"
  fi
}

assert_contains Makefile '^test-static:'
assert_contains Makefile 'tests/verify_external_download_integrity\.sh'
assert_contains Makefile 'tests/test_static_verifiers_without_rg\.sh'
assert_contains Makefile 'tests/verify_test_entrypoints\.sh'
assert_contains Makefile '^test-docker-integration:'
assert_contains Makefile '^test:[[:space:]]+test-static[[:space:]]+test-controller[[:space:]]+test-molecule'

assert_contains .github/workflows/ci-test.yml 'make test-static'
assert_not_contains .github/workflows/ci-test.yml 'tests/verify_docker_xcluster\.sh'
assert_not_contains .github/workflows/ci-test.yml 'tests/verify_backup_restore\.sh'

echo "PASS: fast test entrypoints are wired"

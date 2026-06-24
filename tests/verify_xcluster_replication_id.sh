#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"

  grep -F -n -- "$pattern" "$file" >/dev/null || fail "$file does not contain: $pattern"
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"

  if grep -F -n -- "$pattern" "$file" >/dev/null; then
    fail "$file unexpectedly contains: $pattern"
  fi
}

assert_contains molecule/xcluster/verify.yml 'xcluster_repl_id:'
assert_contains molecule/xcluster/verify.yml "hash('md5')"
assert_not_contains molecule/xcluster/verify.yml 'get_replication_status repl_'
assert_contains molecule/xcluster/verify.yml 'get_replication_status {{ xcluster_repl_id }}'

echo "PASS: xcluster replication ID is derived dynamically"

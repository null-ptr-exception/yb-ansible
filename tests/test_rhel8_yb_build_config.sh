#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"

  grep -Eq "$pattern" "$file" || fail "$file does not contain pattern: $pattern"
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"

  if grep -Eq "$pattern" "$file"; then
    fail "$file still contains forbidden pattern: $pattern"
  fi
}

assert_contains roles/yb-build/defaults/main.yml 'yb_shipper_tag: "2025\.2\.3\.2-b1"'
assert_contains molecule/default/create.yml 'CentOS-Stream-GenericCloud-8-latest\.x86_64\.qcow2'
assert_contains molecule/default/create.yml "'user': 'cloud-user'"
assert_contains molecule/default/tasks/create_vm.yml '--os-variant (centos-stream8|rhel8\.[0-9]+|rhel8-unknown)'
assert_contains molecule/default/tasks/create_vm.yml 'name: cloud-user'
assert_contains molecule/default/verify.yml 'yb_shipper_tag: "2025\.2\.3\.2-b1"'

assert_not_contains README.md 'CentOS 7|RHEL 7'
assert_not_contains docs/solution-overview.md 'CentOS 7|RHEL 7'
assert_not_contains molecule/default/create.yml 'CentOS-7|centos@|ansible_user=centos'
assert_not_contains molecule/default/tasks/create_vm.yml 'CentOS-\\*|vault\.centos\.org|centos7\.0|name: centos'
assert_not_contains molecule/default/molecule.yml 'ansible_user: centos'
assert_not_contains molecule/xcluster/molecule.yml 'ansible_user: centos'
assert_not_contains molecule/backup-restore/molecule.yml 'ansible_user: centos'

echo "PASS: RHEL 8 YugabyteDB build config"

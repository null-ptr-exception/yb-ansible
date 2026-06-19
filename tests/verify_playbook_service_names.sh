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

assert_contains playbooks/verify.yml 'yb_master_service_name: "{{ hostvars[inventory_hostname].yb_master_service_name | default('"'"'yb-master'"'"') }}"'
assert_contains playbooks/verify.yml 'yb_tserver_service_name: "{{ hostvars[inventory_hostname].yb_tserver_service_name | default('"'"'yb-tserver'"'"') }}"'
assert_contains playbooks/verify.yml 'cmd: "systemctl is-active {{ yb_master_service_name }}"'
assert_contains playbooks/verify.yml 'cmd: "systemctl is-active {{ yb_tserver_service_name }}"'
assert_not_contains playbooks/verify.yml 'cmd: systemctl is-active yb-master'
assert_not_contains playbooks/verify.yml 'cmd: "systemctl is-active yb-master"'
assert_not_contains playbooks/verify.yml 'cmd: systemctl is-active yb-tserver'
assert_not_contains playbooks/verify.yml 'cmd: "systemctl is-active yb-tserver"'

echo "PASS: verify playbook service names use role variables"

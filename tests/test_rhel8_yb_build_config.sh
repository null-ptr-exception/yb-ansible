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
    fail "$file still contains forbidden pattern: $pattern"
  elif [[ $? -gt 1 ]]; then
    fail "grep failed for $file with pattern: $pattern"
  fi
}

assert_contains roles/yb-build/defaults/main.yml '^[[:space:]]*yb_shipper_version:[[:space:]]*"2025\.2\.3\.2"[[:space:]]*$'
assert_contains roles/yb-build/defaults/main.yml '^[[:space:]]*yb_shipper_build:[[:space:]]*"b1"[[:space:]]*$'
assert_contains roles/yb-build/defaults/main.yml '^[[:space:]]*yb_shipper_build_number:[[:space:]]*"{{ yb_shipper_build \| regex_replace\('\''\^b'\'', '\'''\''\) }}"[[:space:]]*$'
assert_contains roles/yb-build/defaults/main.yml '^[[:space:]]*yb_shipper_tag:[[:space:]]*"{{ yb_shipper_version }}-{{ yb_shipper_build }}"[[:space:]]*$'
assert_contains roles/yb-build/tasks/main.yml '^[[:space:]]*_yb_installed_version:'
assert_contains roles/yb-build/tasks/main.yml '^[[:space:]]*_yb_installed_build:'
assert_contains roles/yb-build/tasks/main.yml '_yb_installed_version != yb_shipper_version'
assert_contains roles/yb-build/tasks/main.yml '_yb_installed_build != \(yb_shipper_build_number \| string\)'
assert_not_contains roles/yb-build/tasks/main.yml '_yb_expected_version not in|_yb_expected_build not in'
assert_contains roles/yb-build/tasks/main.yml '^[[:space:]]*_yb_post_install_marker:[[:space:]]*"{{ yb_install_dir }}/\.post_install_done_{{ yb_shipper_tag }}"[[:space:]]*$'
assert_contains roles/yb-build/tasks/main.yml 'path: "{{ _yb_post_install_marker }}"'
assert_contains roles/yb-build/tasks/verify.yml '^[[:space:]]*_yb_verify_installed_version:'
assert_contains roles/yb-build/tasks/verify.yml '^[[:space:]]*_yb_verify_installed_build:'
assert_contains roles/yb-build/tasks/verify.yml '_yb_verify_installed_version == yb_shipper_version'
assert_contains roles/yb-build/tasks/verify.yml '_yb_verify_installed_build == \(yb_shipper_build_number \| string\)'
# shellcheck disable=SC2016
assert_contains .github/workflows/build-shipper.yml 'tags: \${{ env\.REGISTRY }}/\${{ env\.IMAGE_NAME }}:\${{ inputs\.yb_version }}-\${{ inputs\.yb_build }}'
# shellcheck disable=SC2016
assert_contains shipper/build.sh 'IMAGE="\${3:-yb-shipper:\${YB_VERSION}-\${YB_BUILD}}"'
assert_contains molecule/default/create.yml 'CentOS-Stream-GenericCloud-8-latest\.x86_64\.qcow2'
assert_contains molecule/default/create.yml '^[[:space:]]*molecule_ssh_user:[[:space:]]+cloud-user[[:space:]]*$'
assert_contains molecule/default/create.yml "'user': molecule_ssh_user"
assert_contains molecule/default/create.yml '{{ molecule_ssh_user }}@{{ item\.address }}'
assert_contains molecule/default/create.yml 'ansible_user={{ molecule_ssh_user }}'
assert_contains molecule/default/tasks/create_vm.yml '--os-variant (centos-stream8|rhel8\.[0-9]+|rhel8-unknown)'
assert_contains molecule/default/tasks/create_vm.yml '^[[:space:]]*-[[:space:]]*name:[[:space:]]+"{{ molecule_ssh_user }}"[[:space:]]*$'
assert_contains molecule/default/verify.yml '^[[:space:]]*yb_shipper_tag:[[:space:]]*"2025\.2\.3\.2-b1"[[:space:]]*$'

assert_not_contains README.md 'CentOS 7|RHEL 7'
assert_not_contains docs/solution-overview.md 'CentOS 7|RHEL 7'
assert_not_contains molecule/default/create.yml 'CentOS-7|centos@|ansible_user=centos'
assert_not_contains molecule/default/tasks/create_vm.yml 'CentOS-\*|vault\.centos\.org|centos7\.0|^[[:space:]]*-[[:space:]]*name:[[:space:]]+centos[[:space:]]*$'
assert_not_contains molecule/default/molecule.yml 'ansible_user: centos'
assert_not_contains molecule/xcluster/molecule.yml 'ansible_user: centos'
assert_not_contains molecule/backup-restore/molecule.yml 'ansible_user: centos'

echo "PASS: RHEL 8 YugabyteDB build config"

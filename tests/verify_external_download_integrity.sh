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

assert_contains controller/Dockerfile 'ARG S5CMD_SHA256='
assert_contains controller/Dockerfile 's5cmd.*sha256sum -c -|sha256sum -c -.*s5cmd'
assert_contains controller/Dockerfile 'ARG MINIO_SHA256='
assert_contains controller/Dockerfile 'minio.*sha256sum -c -|sha256sum -c -.*minio'

assert_contains roles/common/defaults/main.yml '^s5cmd_checksum: "sha256:'
assert_contains roles/common/tasks/main.yml 'checksum: "{{ s5cmd_checksum }}"'

assert_contains molecule/backup-restore/verify.yml 'molecule_minio_checksum: "sha256:'
assert_contains molecule/backup-restore/verify.yml 'checksum: "{{ molecule_minio_checksum }}"'

assert_contains molecule/default/create.yml 'base_img_checksum: "sha256:'
assert_contains molecule/default/create.yml 'checksum: "{{ base_img_checksum }}"'

assert_not_contains shipper/Dockerfile '^ADD https://'
assert_contains shipper/Dockerfile '(curl|wget).*(yugabyte|YB_VERSION).*(tar\.gz|YB_ARCH)'
assert_contains shipper/Dockerfile 'YB_SHA256'
assert_contains shipper/build.sh '--build-arg "YB_SHA256='

echo "PASS: external downloads declare integrity checks"

#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"

  grep -Eq "$pattern" "$file" || fail "$file does not contain: $pattern"
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"

  if grep -Eq "$pattern" "$file"; then
    fail "$file unexpectedly contains: $pattern"
  fi
}

assert_contains .github/workflows/build-shipper.yml 'default: "2025\.2\.3\.2"'
assert_contains .github/workflows/build-shipper.yml 'default: "b1"'
assert_contains .github/workflows/build-shipper.yml 'tags: \$\{\{ env\.REGISTRY \}\}/\$\{\{ env\.IMAGE_NAME \}\}:\$\{\{ inputs\.yb_version \}\}-\$\{\{ inputs\.yb_build \}\}'
assert_not_contains .github/workflows/build-shipper.yml 'tags: \$\{\{ env\.REGISTRY \}\}/\$\{\{ env\.IMAGE_NAME \}\}:\$\{\{ inputs\.yb_version \}\}$'

assert_contains shipper/Dockerfile 'ARG YB_VERSION=2025\.2\.3\.2'
assert_contains shipper/Dockerfile 'ARG YB_BUILD=b1'

assert_contains shipper/build.sh 'IMAGE="\$\{3:-yb-shipper:\$\{YB_VERSION\}-\$\{YB_BUILD\}\}"'
assert_contains shipper/build.sh 'ghcr\.io/<org>/yb-shipper:\$\{YB_VERSION\}-\$\{YB_BUILD\}'
assert_not_contains shipper/build.sh 'ghcr\.io/<org>/yb-shipper:\$\{YB_VERSION\}"$'

echo "PASS: yb-shipper 2025.2.3.2-b1 build config"

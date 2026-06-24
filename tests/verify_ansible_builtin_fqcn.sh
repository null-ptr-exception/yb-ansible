#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

matches="$(
  grep -R -I -s -n -E \
    --exclude-dir=.cache \
    '^[[:space:]]+(debug|set_fact|command|fail|import_tasks):' \
    roles playbooks molecule || true
)"

if [ -n "$matches" ]; then
  echo "$matches" >&2
  fail "Found builtin task plugins without ansible.builtin FQCN"
fi

echo "PASS: ansible.builtin FQCN rule"

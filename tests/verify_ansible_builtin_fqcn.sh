#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

matches="$(rg -n '^[[:space:]]+(debug|set_fact|command|fail|import_tasks):' roles playbooks molecule || true)"

if [ -n "$matches" ]; then
  echo "$matches" >&2
  fail "Found builtin task plugins without ansible.builtin FQCN"
fi

echo "PASS: ansible.builtin FQCN rule"

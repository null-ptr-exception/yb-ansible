#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

file="molecule/default/create.yml"

rg -n "ssh_pub_key_env" "$file" >/dev/null || fail "missing ssh_pub_key_env fallback in $file"
rg -n "lookup\\('file', ssh_identity_file ~ '\\.pub'\\)" "$file" >/dev/null || fail "missing identity-file pubkey fallback in $file"
! rg -n "rophy" "$file" >/dev/null || fail "hardcoded fallback pubkey is still present in $file"

echo "PASS: molecule SSH key defaults follow the identity file"

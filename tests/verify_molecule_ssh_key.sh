#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

file="molecule/default/create.yml"

grep -n -E "ssh_pub_key_env" "$file" >/dev/null || fail "missing ssh_pub_key_env fallback in $file"
grep -n -E "lookup\\('file', ssh_identity_file ~ '\\.pub', errors='ignore'\\)" "$file" >/dev/null || fail "missing identity-file pubkey fallback in $file"
grep -n -E "Fail if Molecule SSH public key is unavailable" "$file" >/dev/null || fail "missing empty pubkey guard in $file"
! grep -n -E "rophy" "$file" >/dev/null || fail "hardcoded fallback pubkey is still present in $file"

echo "PASS: molecule SSH key defaults follow the identity file"

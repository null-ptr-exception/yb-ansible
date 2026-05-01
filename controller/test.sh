#!/usr/bin/env bash
set -euo pipefail

IMAGE="yb-ansible-controller:test"

echo "=== Building controller image ==="
docker build -t "$IMAGE" "$(dirname "$0")"

echo "=== Verifying tools ==="
docker run --rm "$IMAGE" bash -c '
  set -e
  failed=0
  for cmd in ansible crane yq jq git ssh rsync curl wget dig ping nc traceroute ip vim; do
    if command -v "$cmd" > /dev/null 2>&1; then
      printf "  %-12s OK\n" "$cmd"
    else
      printf "  %-12s MISSING\n" "$cmd"
      failed=1
    fi
  done
  exit $failed
'

echo "=== All checks passed ==="

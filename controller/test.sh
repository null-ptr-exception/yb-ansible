#!/usr/bin/env bash
set -euo pipefail

IMAGE="yb-ansible-controller:test"
DOCKER_BUILD_ARGS="${DOCKER_BUILD_ARGS:-}"

echo "=== Building controller image ==="
# shellcheck disable=SC2086
docker build $DOCKER_BUILD_ARGS -t "$IMAGE" "$(dirname "$0")"

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

#!/usr/bin/env bash
set -euo pipefail

YB_VERSION="${1:?Usage: build.sh <version> <build> [image-name]}"
YB_BUILD="${2:?Usage: build.sh <version> <build> [image-name]}"
IMAGE="${3:-yb-shipper:${YB_VERSION}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Building ${IMAGE} with YugabyteDB ${YB_VERSION}-${YB_BUILD}..."

docker build \
  --build-arg "YB_VERSION=${YB_VERSION}" \
  --build-arg "YB_BUILD=${YB_BUILD}" \
  -t "${IMAGE}" \
  "${SCRIPT_DIR}"

echo "Built: ${IMAGE}"
echo ""
echo "To push to a registry:"
echo "  docker tag ${IMAGE} ghcr.io/<org>/yb-shipper:${YB_VERSION}"
echo "  docker push ghcr.io/<org>/yb-shipper:${YB_VERSION}"

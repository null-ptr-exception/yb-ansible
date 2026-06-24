#!/usr/bin/env bash
set -euo pipefail

YB_VERSION="${1:?Usage: build.sh <version> <build> [image-name]}"
YB_BUILD="${2:?Usage: build.sh <version> <build> [image-name]}"
IMAGE="${3:-yb-shipper:${YB_VERSION}-${YB_BUILD}}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YB_SHA256="${YB_SHA256:-ea23027f6cc46f0b87123e712f6a0cdbb9676c84d6bc8f4f0124b104de556f97}"

echo "Building ${IMAGE} with YugabyteDB ${YB_VERSION}-${YB_BUILD}..."

docker build \
  --build-arg "YB_VERSION=${YB_VERSION}" \
  --build-arg "YB_BUILD=${YB_BUILD}" \
  --build-arg "YB_SHA256=${YB_SHA256}" \
  -t "${IMAGE}" \
  "${SCRIPT_DIR}"

echo "Built: ${IMAGE}"
echo ""
echo "To push to a registry:"
echo "  docker tag ${IMAGE} ghcr.io/<org>/yb-shipper:${YB_VERSION}-${YB_BUILD}"
echo "  docker push ghcr.io/<org>/yb-shipper:${YB_VERSION}-${YB_BUILD}"

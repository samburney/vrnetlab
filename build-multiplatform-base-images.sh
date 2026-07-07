#!/usr/bin/env bash
# this script builds the vrnetlab base container image
# that is used in the dockerfiles of the NOS images

set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <version>"
    exit 1
fi

VERSION=$1
FINAL_IMAGE="ghcr.io/srl-labs/vrnetlab-base:${VERSION}"
REGISTRY_NAME="vrnetlab-base-registry"
NETWORK_NAME="vrnetlab-build-net"
BUILDER_NAME="vrnetlab-base-builder"
BUILDKIT_CONFIG=$(mktemp /tmp/buildkitd-XXXXXX.toml)

cat > "${BUILDKIT_CONFIG}" << EOF
[registry."${REGISTRY_NAME}:5000"]
  http = true
  insecure = true
EOF

cleanup() {
    echo "--> Tearing down build infrastructure"
    docker rm -f "${REGISTRY_NAME}" 2>/dev/null || true
    docker buildx rm "${BUILDER_NAME}" 2>/dev/null || true
    docker network rm "${NETWORK_NAME}" 2>/dev/null || true
    rm -f "${BUILDKIT_CONFIG}"
}
trap cleanup EXIT SIGINT SIGTERM

echo "--> Creating build network"
docker network rm "${NETWORK_NAME}" 2>/dev/null || true
docker network create "${NETWORK_NAME}"

echo "--> Starting local registry"
docker rm -f "${REGISTRY_NAME}" 2>/dev/null || true
docker run -d \
    --name "${REGISTRY_NAME}" \
    --network "${NETWORK_NAME}" \
    -p 5000:5000 \
    registry:2

echo "--> Creating multi-platform builder"
docker buildx rm "${BUILDER_NAME}" 2>/dev/null || true
docker buildx create \
    --name "${BUILDER_NAME}" \
    --driver docker-container \
    --driver-opt network="${NETWORK_NAME}" \
    --config "${BUILDKIT_CONFIG}" \
    --use

echo "--> Building and pushing multi-platform image to local registry"
docker buildx build \
    --platform linux/amd64,linux/arm64 \
    --push \
    -t "${REGISTRY_NAME}:5000/vrnetlab-base:${VERSION}" \
    -f vrnetlab-base.dockerfile .

echo "--> Pulling platform variants and retagging"
for PLATFORM in linux/amd64 linux/arm64; do
    ARCH="${PLATFORM#linux/}"
    docker pull --platform "${PLATFORM}" "localhost:5000/vrnetlab-base:${VERSION}"
    docker tag "localhost:5000/vrnetlab-base:${VERSION}" "${FINAL_IMAGE}"
    docker tag "localhost:5000/vrnetlab-base:${VERSION}" "${FINAL_IMAGE}-${ARCH}"
done

echo "--> Done: ${FINAL_IMAGE}, ${FINAL_IMAGE}-amd64, ${FINAL_IMAGE}-arm64"

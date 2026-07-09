#!/usr/bin/env bash
set -e

REPO="vrnetlab/mikrotik_routeros"

make

docker images --format "{{.Tag}}" "${REPO}" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-amd64$' | while read -r tag; do
    VERSION="${tag%-amd64}"
    if ! docker image inspect "${REPO}:${VERSION}-arm64" &>/dev/null; then
        echo "Tagging ${REPO}:${tag} as ${REPO}:${VERSION}"
        docker tag "${REPO}:${tag}" "${REPO}:${VERSION}"
    fi
done
